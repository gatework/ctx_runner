# 报告文档与发布边界

## 问题与目标

Report 保留独立的 serializable 递归实现，绕过 Document 对循环、冲突键、深度和不透明值的校验。当前探针确认：循环检查点产生 SystemStackError；JSON 编码或转换失败时旧 complete 留在磁盘；Object.new 被写成对象描述字符串。重复转换还让返回摘要与 JSON 使用两套键和值表示。

用 Document 作为唯一 JSON 值边界，Report 只负责发布及恢复。摘要在展示回调、返回值和最终文件中使用同一份深冻结、字符串键文档；Time/Data 等已有文档能力继续保留。明确迁移当前全部消费者，不保留 serializable、双格式读取或兼容参数。内部采集和领域结果仍使用自己的类型；文档转换发生在报告与进度交付边界。

## 必须保持的行为

- finish 先发布未完成检查点，再调用展示，再提交最终 JSON；报告完成不等于领域健康。
- 转换、JSON 编码、普通异常、Interrupt、throw/非局部退出都不能让旧 complete 代表未完成的新发布。非法路径在任何清理副作用之前拒绝。
- checkpoint 必须是带有非空、非 complete 状态的对象；finalize 的恢复参数遵守同一契约，不能用成功文档恢复一次失败提交。
- 仅完成文件替换而目录同步未确认时恢复检查点；恢复失败仍保留主异常并通过 recovery_failed? 显式报告。已有未完成检查点不因新输入校验失败被删除。
- 输入不冻结、不被回调修改后重新读取；返回/展示文档深度不可变。Document 的 128 层预算是 JSON 编码的嵌套边界；超限为 ArgumentError，不是栈溢出。
- write_execution 使用相同文档校验，失败继续交给 Execution 停止后续写入；不改变命令记账、回读或禁止重放规则。
- Batch 的 Completion.status 仍为 Ruby 符号；Completion.summary 和进度交付文档使用字符串键/状态。设备采集结果与领域 Report#write 的 Ruby 结构不改变。
- 连接器独立支持 Ruby 3.4，不依赖 Runner。其 Collect::Progress 直接接收文档，不自行引入转换器。
- lib 注释中文、业务字面量英文；Wireless 仅迁移消费协议，不扩大此前语言规范的八模块范围。

## 验收与范围

Runner 现有取消/路径/恢复/设备执行测试以及新增实际文件回归通过；两个领域完整默认 rake 和连接器完整 script/ci 通过。从实际 checkout 验证普通 CLI，再构建精确候选、比对打包源码和隔离安装。无需真实设备、远程发布或版本上线；不提交或推送。保留全部已有 WIP。

新的接口会要求外部摘要/进度消费者改用字符串键；明确在 README/CHANGELOG 中记录并以当前真实消费链验证，不提供符号键回退。
