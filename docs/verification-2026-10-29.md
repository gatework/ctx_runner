# 九模块契约改造验证记录

日期：2026-10-29。环境：Linux x86_64；运行时均由 RVM 安装。工作区为 `/root/gatework-contracts-20261029`，各仓库开发分支为 `contracts/unify`。本记录描述发布前的本地验证；远端 CI 和发布结果以对应版本标签及 GitHub Release 为准。

契约、职责和迁移说明见 [contracts-2026-10-29.md](contracts-2026-10-29.md)。本记录区分源码测试、独立安装与尚未运行的外部环境。

## 运行时

- Ruby 4.0.6，revision `03b6d3f889`：九模块完整检查。
- Ruby 3.4.12，revision `366f5fdc00`：最低 Ruby 版本为 3.4 的 ctx_cli、expect-pty、net-connector。
- Bundler 4.0.16；各仓库分别使用自己的 Gemfile 和已解析依赖。跨仓库源码联调另使用工作区 Gemfile，不能替代独立安装。
- 此环境的 RVM 选择命令使用完整名称，例如 `rvm use ruby-4.0.6`，避免旧版 RVM 对裸 `4.0.6` 的识别问题。

## 源码与工具检查

用例数为 RSpec examples 或 Minitest runs；Ruby 3.4 的重复运行不计入 Ruby 4 总数。

| 仓库 | Ruby 4.0.6 用例 | Ruby 3.4.12 用例 | 其他检查 |
| --- | ---: | ---: | --- |
| expect-ruby | 634 | 634 | lint、API/RBS；4.0.6 完整 script/ci、示例、七组 smoke benchmark |
| net-connector | 1284 | 1284 | lint、行/分支覆盖率门槛；4.0.6 源码/历史/包扫描、actionlint、benchmark、隔离包 |
| ctx_cli | 36 | 36 | lint、离线示例、rake build |
| ctx_parser | 140 | 不适用 | lint、离线示例、rake build |
| ctx_driver | 49 | 不适用 | lint、离线及真实 PTY 示例、rake build |
| ctx_runner | 78 | 不适用 | lint、离线示例、rake build |
| ctx_checker | 704 | 不适用 | lint、离线及真实 PTY 示例、rake build |
| vxlan | 482 | 不适用 | lint、离线示例、普通 CLI、rake build |
| wireless-rb | 340 | 不适用 | lint、离线示例、普通 CLI、rake build |

Ruby 4.0.6 共 3,747 个用例通过；Ruby 3.4.12 的三个库共 1,954 个用例通过。Parser/Driver/Runner/Checker/VXLAN/Wireless 的声明下限为 Ruby 4.0.6，不将它们列为 Ruby 3.4 已支持。

net-connector 的完整检查曾因环境缺少 GNU time 停在 benchmark；安装系统 time 后，续跑 `rake benchmark:smoke package:verify` 通过。测试、扫描和 lint 在此前已通过，分步日志共同构成完整结果。Ruby 3.4 只声明实际运行的 `bundle exec rake` 及其覆盖率检查，不将 Ruby 4 的包检查冒充为 Ruby 3.4 包检查。

原生 PTY 用例使用本地模拟设备，经过真实 expect-pty 和连接器；子进程使用 `--disable-gems`，避免把不需要的 Bundler 启动纳入两秒登录时限。没有访问网络设备。

## 独立安装

七个 ctx/领域仓库各自的 `script/verify_package.rb` 均通过，显式提供未发布依赖候选。Expect 和连接器的隔离安装由各自 CI/package 任务完成。

VXLAN/Wireless 另验证无连接器安装时的离线解析、review、帮助和计划输出，再安装连接器验证配置初始化、权限、清单预览与错误出口。安装过程不使用相邻源码目录；CLI 候选逐文件校验一致。

统一验证入口为：

```sh
rvm use ruby-4.0.6
ruby ctx_runner/script/verify_stack.rb /root/gatework-contracts-20261029 /root/gatework-contracts-20261029/.artifacts
```

脚本从九个 checkout 构建候选，检查全部运行依赖约束，在临时 GEM_HOME 进行普通安装和最小 Bundler 安装。两种消费方式均检查精确候选版本、来源路径、三个领域共用 Batch、schema 3 往返、离线示例、普通 CLI 和真实 PTY。运行依赖来自已解析的本地 gem 缓存；候选不能被线上旧版替换。

最终包及 SHA256 记录在工作区 `.artifacts/manifest.json`，最终整体验证日志为 `.validation/stack-install-final.log`。manifest 中的 revision 是各仓库基线 HEAD；未提交的最终内容由候选包摘要确定。

## 重点回归

- Result 的 covered_scopes 参与 Data 值相等、hash、with 与模式匹配；不再由 ScopedResult 绕开值协议。
- Snapshot 对空请求、全部不可用、部分事实、关闭失败及有证据的不适用分别聚合；移除伪造的 collection 观测。
- Target 白名单、不可变输入、严格时刻与 schema 校验拒绝旧格式、未知身份字段、伪造的聚合结论及越界日期。
- 被连接器吞掉的回调失败不会被后续关闭失败覆盖；取消、重复回调、持久化失败和执行后记账失败仍保留既有事实。
- 共用 Apply 验证具名项和文件摘要，从领域增量重新生成命令；取消不连接、不重放、凭据空值回退及平台 enable password 均有消费端回归。
- 无线并发报告完整汇总、稳定排序；同一配置的模板计划共享指纹；新的报告重新计算指纹。
- Wireless 独立 review 缺失维度注册表 require 的问题由子进程回归复现，补齐显式加载后通过；不能依赖先加载根入口。
- net-connector 既有归档测试在基线上复现同一时钟粒度内覆写漏检；投递后在原描述符上复核摘要，完整测试通过。该修复增加一次有界读取，不声称零成本或对外部并发写入提供事务锁。

## 日志与范围

工作区 `.validation/` 保留原始日志：

- `*-locked-rake.log`：各仓库独立 Bundler 检查；VXLAN/Wireless 的最终结果使用 `*-final-rake.log`。
- `*-ruby34-rake.log`：Ruby 3.4 三库检查。
- `expect-ci.log`、`connector-ci.log`、`connector-package.log`：底层两库完整检查步骤。
- `*-build.log`、`*-package.log`、`stack-install-final.log`：构建、逐包安装和最终候选组合验证。
- `connector-baseline-mutation.log`、`wireless-review-loading-regression.log`：修复前的回归复现，保留失败输出以便追溯。

Wireless review（100/500/1000 模板）和 VXLAN fabric（100/1000/3000 组）基准的功能断言通过；本机共享负载下不据此宣称性能提升。

本地未运行 macOS、真实交换机/无线控制器、外部 SSH 或 PostgreSQL 联机矩阵。本次变更包含破坏性接口与 schema 3 迁移，旧报告及计划必须重新生成。本地验证不能替代发布标签对应的 CI 与制品读回校验。
