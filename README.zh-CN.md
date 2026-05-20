# Knot Agent

**面向企业数字员工的本地优先运行脚手架。**

[English README](README.md)

Knot Agent 为 Codex 驱动的 agent 提供 workspace、知识布局、权限契约、IM 路由、交付边界、runtime 检查和 setup 流程。目标不是做一个聊天入口，而是让 agent 能够跨用户、跨渠道作为可持续的业务角色运行。

这个仓库是 Codex 的轻量起点，只保存运行指南、setup skills、runtime 检查和 workspace 布局规则。组件仓库、运行时凭证、日志、客户数据和工作文件都保留在本地，不属于这个 scaffold。

## 从这里开始

1. 在 Knot 根目录启动 Codex。
2. 先读 `AGENTS.md`；它是 workspace 的操作指南。
3. 使用 `knot-setup` skill 安装或修复 workspace。
4. setup 完成后，使用 `knot-workflow` 路由知识、IM、附件和交付物任务。

## 边界

- 源码仓库放在 `components/`。
- 用户文件、草稿、交付物和任务状态放在 `workspace/`。
- runtime 配置、日志、socket 和本地密钥放在 `runtime/`。
- 不要把生成物或临时工作放在仓库根目录。

## License

Apache License 2.0。见 [LICENSE](LICENSE)。
