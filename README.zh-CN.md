# Knot Agent

**面向企业数字员工的本地优先运行脚手架。**

[English README](README.md)

Knot Agent 为 Codex 驱动的 agent 提供 workspace、知识布局、权限契约、IM 路由、交付边界、runtime 检查和 setup 流程。目标不是做一个聊天入口，而是让 agent 能够跨用户、跨渠道作为可持续的业务角色运行。

这个仓库是 Codex 的轻量起点，只保存运行指南、setup skills、runtime 检查和 workspace 布局规则。组件仓库、运行时凭证、日志、客户数据和工作文件都保留在本地，不属于这个 scaffold。

## 从这里开始

1. 在 Knot 根目录启动 Codex。
2. 先读 `AGENTS.md`；它是 workspace 的操作指南。
3. 使用 `knot-setup` skill 安装或修复 Codex 默认配置、skills 和 workspace。
4. setup 完成后，使用 `knot-workflow` 路由知识、IM、附件和交付物任务。

## 边界

- 源码仓库放在 `components/`；经审查的固定版本记录在
  `components.lock` 中，installer 与 doctor 都会校验该文件。
- 用户文件、草稿、交付物和可恢复工作状态放在 `workspace/`。
- runtime 配置、日志、socket 和本地密钥放在 `runtime/`。
- 不要把生成物或临时工作放在仓库根目录。

## 控制面

Codex session history 是对话 transcript 的事实来源。Codex cwd/sandbox 是主要文件访问边界。Knot workspace helper 负责身份到 workspace 的路由，delivery helper 负责出站附件边界，Knot event log 只为确定性边界动作记录紧凑审计行。默认不生成 task records。

## 企业数据流

Knot 只收窄四类企业集成流：IM 消息、文件、知识和审计证据。每类流都经过明确的 workspace、交付或审计边界。见 [`docs/architecture/enterprise-data-flow.md`](docs/architecture/enterprise-data-flow.md)。

## 运营

- 发布门禁：[`docs/ops/release-gate.md`](docs/ops/release-gate.md)
- 组件同步：[`docs/ops/component-sync.md`](docs/ops/component-sync.md)
- 部署输入：[`docs/ops/deployment-inputs.md`](docs/ops/deployment-inputs.md)
- IM smoke 测试：[`docs/ops/im-smoke-sop.md`](docs/ops/im-smoke-sop.md)
- 安全模型：[`docs/security/security-model.md`](docs/security/security-model.md)
- 审计事件 schema：[`docs/schemas/audit-event.schema.json`](docs/schemas/audit-event.schema.json)

## License

Apache License 2.0。见 [LICENSE](LICENSE)。
