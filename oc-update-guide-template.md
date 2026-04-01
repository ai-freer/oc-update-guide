# OpenClaw 升级管理指南

> 本文档供用户和 agents 在升级前参考。最后更新：YYYY-MM-DD，当前版本 X.Y.Z。
>
> **首次初始化时由 oc-update-guide skill 自动生成，用户审阅后补充完善。**

## 基本信息

| 字段 | 值 |
|------|-----|
| 工具名 | `openclaw` |
| 当前版本 | `X.Y.Z` |
| 安装方式 | `npm i -g openclaw` |
| 全局安装路径 | `/usr/lib/node_modules/openclaw/` |
| 配置文件路径 | `~/.openclaw/openclaw.json` |
| 服务管理 | `systemctl --user restart openclaw-gateway.service` |
| Changelog 位置 | `${install_path}/CHANGELOG.md` 或 GitHub URL |
| Patch 入口脚本 | `~/.openclaw/workspace/patches/apply-patches.sh` |

## 升级原则

- **不需要每个版本都跟**。建议每 1-2 周检查一次 changelog，只在有必要时升级。
- **跳过预发布版本**（beta / rc / canary）。
- **优先关注 Breaking 和 Fixes 区块**，搜索你用的功能关键词。
- **安全修复是升级的主要理由**。
- **新发布版本等 2-3 天**再升级，观察是否有回退报告。

## 功能关键词

升级评估时搜索以下关键词，命中的修复/变更需重点关注：

```
keyword1, keyword2, keyword3
```

> 示例：Telegram, Feishu, heartbeat, pi-ai, reaction

## 升级前检查

### 查看 changelog

```bash
cat /usr/lib/node_modules/openclaw/CHANGELOG.md
```

重点看：
- `### Breaking` — 是否有影响你的破坏性变更
- `### Fixes` — 是否有你遇到的 bug 的修复
- 搜索上方关键词列表

### 检查当前版本

```bash
openclaw --version
npm list -g openclaw
```

## 升级流程

```bash
# 1. 备份配置
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%Y%m%d_%H%M%S)

# 2. 指定版本升级（不要用 @latest）
npm i -g openclaw@X.Y.Z

# 3. 运行 doctor
openclaw doctor

# 4. 重启服务（按实际部署环境，以下为 Linux/systemd 示例）
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user restart openclaw-gateway.service

# 5. 健康检查
openclaw health
openclaw status
```

## 回滚

```bash
npm i -g openclaw@<旧版本号>
openclaw doctor
# 重启服务（按实际部署环境，以下为 Linux/systemd 示例）
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user restart openclaw-gateway.service
```

## 升级不会影响的东西

- `~/.openclaw/openclaw.json` — 配置文件独立于代码目录，npm 升级不会覆盖
- `~/.openclaw/workspace/` — 工作目录完全独立
- systemd service 配置 — drop-in 文件不受影响

## 升级会覆盖的东西

- `/usr/lib/node_modules/openclaw/` — 整个代码目录会被替换
- **所有本地 patch 会被覆盖** — 需通过 patch 入口脚本重打

## 本地 Patch 清单

> 列出所有对安装目录做的本地修改。每条 patch 需记录：目标文件、修改内容、
> 验证命令、对应 Issue。

统一入口：`${patch_script_path}`（幂等，服务重启时自动执行）

| # | Patch 名称 | 目标文件 | 验证命令 | Issue |
|---|-----------|---------|---------|-------|
| 1 | 示例 patch | `dist/target.js` | `grep -c "marker" ${target_file}` 返回 > 0 | #12345 |

### Patch 失败处理

patch 基于字符串匹配，上游文件结构变化会导致静默不匹配。重启后如发现异常：

```bash
# 手动重打所有 patch
bash ${patch_script_path}

# 逐条验证
# ...（按上方清单的验证命令逐项检查）
```

## 升级后需手动修复的文件

> 安装目录中被覆盖但无法通过 patch 脚本自动处理的修改

| 文件 | 修改内容 | 原因 |
|------|---------|------|
| `path/to/file` | 具体修改 | 为什么需要改 |

**快速修复命令：**
```bash
# sed -i 's/old/new/g' ${target_file}
```

## 已知升级陷阱

> 记录升级过程中遇到过的问题，供后续参考

### 陷阱 1：标题

描述问题和解决方案：

```bash
# 修复命令
```

## 版本选择建议

| 场景 | 建议 |
|------|------|
| 有你遇到的 bug 被修复 | 升级到包含修复的最小版本 |
| 大量安全修复 | 尽快升级 |
| 只有新功能、没有相关修复 | 可以跳过 |
| 刚发布的版本 | 等 2-3 天观察 |

## Breaking Changes 速查

> 累积记录各版本的破坏性变更及影响评估

| 版本 | 变更 | 对我们影响 |
|------|------|-----------|
| X.Y | 变更描述 | ✅/❌/⚠️ 说明 |

## 版本升级检查记录

> 此章节记录每次版本评估结论，持续覆盖复写。有新版本评估后，删除旧记录，写入新记录。

### 当前评估：X.Y.Z（检查日期：YYYY-MM-DD）

**结论：✅ 建议升级 / ⏭️ 可跳过 / ❌ 不建议**

**当前版本：** A.B.C
**目标版本：** X.Y.Z（发布日期，距今 N 天）

**升级理由：**

1. 理由 1
2. 理由 2

**Breaking Change 确认：**
- 无影响 / 需处理 XXX

**升级后需做的事：**
1. 备份配置
2. 指定版本升级
3. doctor 迁移
4. 重启服务（自动重打 patch）
5. 验证 patch
6. 手动修复
7. 健康检查
