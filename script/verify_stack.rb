# frozen_string_literal: true

require "rubygems/package"
require "json"
require "digest"
require "fileutils"
require "tmpdir"
require "rbconfig"
require "open3"

# 显式指定工作区和产物目录；不探测相邻源码，不连接设备，不发布 gem。
workspace, output = ARGV.map { |path| File.expand_path(path) }
abort "Usage: ruby script/verify_stack.rb WORKSPACE OUTPUT" unless workspace && output && ARGV.size == 2
repositories = %w[expect-ruby ctx_cli ctx_parser ctx_driver ctx_runner ctx_checker net-connector vxlan wireless-rb]
ruby = RbConfig.ruby
FileUtils.mkdir_p(output)
artifacts = repositories.map do |repository|
  checkout = File.join(workspace, repository)
  gemspec = Dir[File.join(checkout, "*.gemspec")].fetch(0)
  spec = Gem::Specification.load(gemspec)
  artifact = File.join(output, "#{spec.full_name}.gem")
  system(ruby, "-S", "gem", "build", gemspec, "--output", artifact, chdir: checkout, exception: true)
  revision, status = Open3.capture2("git", "-C", checkout, "rev-parse", "HEAD")
  abort "Cannot identify source revision" unless status.success?
  { repository: repository, revision: revision.strip, package: artifact, name: spec.name,
    version: spec.version.to_s, sha256: Digest::SHA256.file(artifact).hexdigest }
end

# 仅缓存解析后的运行依赖；候选必须满足每一条边，不能由线上版本替换。
candidates = artifacts.to_h { |entry| [ entry[:name], Gem::Package.new(entry[:package]).spec ] }
pending = candidates.values.flat_map(&:runtime_dependencies)
caches, selected = [], {}
until pending.empty?
  dependency = pending.shift
  spec = candidates[dependency.name] || selected[dependency.name] || Gem::Specification.find_all_by_name(dependency.name, dependency.requirement).max_by(&:version)
  abort "Missing or incompatible dependency: #{dependency}" unless spec && dependency.matches_spec?(spec)
  next if candidates.key?(dependency.name) || selected.key?(dependency.name)
  selected[dependency.name] = spec
  caches << spec.cache_file if File.file?(spec.cache_file)
  abort "Missing dependency cache: #{spec.full_name}" unless spec.default_gem? || File.file?(spec.cache_file)
  pending.concat(spec.runtime_dependencies)
end

Dir.mktmpdir("gatework-install-") do |home|
  env = ENV.to_h.keys.grep(/\A(?:BUNDLE_|BUNDLER_|RUBY)/).to_h { |key| [ key, nil ] }
  env.merge!("GEM_HOME" => home, "GEM_PATH" => home, "RUBYOPT" => nil, "RUBYLIB" => nil)
  packages = caches.uniq + artifacts.map { |entry| entry[:package] }
  system(env, ruby, "-S", "gem", "install", "--local", "--no-document", "--ignore-dependencies", *packages, chdir: home, exception: true)
  # 每个 capability 可独立加载；尤其 CLI 不能通过宿主依赖才恰巧成功。
  system(env, ruby, "-e", 'require "ctx_cli/apply"; abort "CLI loaded a host dependency" if defined?(CtxRunner) || defined?(CtxParser) || defined?(Net::Connector)', chdir: home, exception: true)
  smoke = <<~'RUBY'
    require "ctx_parser"
    require "ctx_driver"
    require "ctx_runner"
    require "ctx_checker"
    require "ctx_cli"
    require "vxlan"
    require "wireless"
    require "net/connector"
    require "expect/pty"
    require "rbconfig"
    require "json"

    expected = JSON.parse(File.read(ARGV.fetch(0)))
    expected.each do |entry|
      spec = Gem.loaded_specs.fetch(entry.fetch("name"))
      abort "Version mismatch" unless spec.version.to_s == entry.fetch("version")
      abort "Loaded checkout" unless File.realpath(spec.full_gem_path).start_with?(File.realpath(ENV.fetch("GEM_HOME")) + "/")
      spec.runtime_dependencies.each do |dependency|
        installed = Gem.loaded_specs[dependency.name] || Gem::Specification.find_by_name(dependency.name, dependency.requirement)
        abort "Unsatisfied dependency" unless dependency.matches_spec?(installed)
      end
    end

    writer = Object.new
    def writer.write(result, snapshot:); end
    progress = Object.new
    def progress.start(device); end
    def progress.result(result); end
    [ [ CtxChecker, :interfaces ], [ Vxlan, :interfaces ], [ Wireless, :access_points ] ].each do |domain, name|
      target = { host: "192.0.2.1", platform: "cisco_nxos" }
      options = domain == Vxlan ? { fabric_key: "test" } : {}
      observation = domain::Observation.new(name: name, status: :complete)
      snapshot = domain::Snapshot.new(target: target, observations: { name => observation }, observed_at: Time.now.utc, **options)
      device = { "host" => "192.0.2.1", "name" => "fixture", "platform" => "cisco_nxos" }
      batch = CtxRunner::Batch.new(report: writer, progress: progress, requested: [ device ])
      result = batch.collect(device) { snapshot }
      abort "Domain snapshot cannot participate in Batch" unless result[:status] == :complete && result[:report_saved]
      abort "Synthetic collection observation" if snapshot.observations.key?(:collection)
      document = CtxRunner::Evidence.wrap({ status: :complete, target: device, snapshot: snapshot }, kind: "collection")
      CtxRunner::Evidence.validate(document, names: snapshot.observations.keys) { }
    end

    Expect.spawn(RbConfig.ruby, "--disable-gems", "-e", 'STDOUT.sync = true; puts "ready"; puts "reply:#{$stdin.gets&.strip}"', raw: true) do |session|
      abort "PTY prompt missing" unless session.expect("ready", timeout: 5).matched?
      session.puts("contract")
      abort "PTY response missing" unless session.expect("reply:contract", timeout: 5).matched?
      abort "PTY child failed" unless session.soft_close(timeout: 5)&.success?
    end

    %w[ctx_parser ctx_driver ctx_runner ctx_checker ctx_cli vxlan wireless-rb].each do |name|
      spec = Gem.loaded_specs.fetch(name)
      Dir[File.join(spec.full_gem_path, "examples/**/*.rb")].sort.each { |file| load file }
    end
    %w[vxlan wireless net-backup].each do |name|
      system(RbConfig.ruby, File.join(ENV.fetch("GEM_HOME"), "bin", name), "--help", exception: true)
    end
    puts "Installed stack: dependency versions, domain Batch, schema 4, examples, CLI and real PTY passed"
  RUBY
  manifest = File.join(output, "manifest.json")
  File.write(manifest, JSON.pretty_generate(artifacts) + "\n")
  file = File.join(home, "smoke.rb")
  File.write(file, smoke)
  system(env, ruby, file, manifest, chdir: home, exception: true)
  # 最小消费方仅声明发布包，不借用工作区加载路径或开发依赖。
  gemfile = "source \"https://rubygems.org\"\n" + artifacts.map { |entry| "gem #{entry[:name].inspect}, #{("= " + entry[:version]).inspect}, require: false" }.join("\n") + "\n"
  File.write(File.join(home, "Gemfile"), gemfile)
  system(env, ruby, "-S", "bundle", "lock", "--local", chdir: home, exception: true)
  system(env, ruby, "-S", "bundle", "exec", ruby, file, manifest, chdir: home, exception: true)
end
puts "Verified candidate checksums: #{File.join(output, 'manifest.json')}"
