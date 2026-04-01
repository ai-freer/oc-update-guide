---
name: oc-update-guide
description: >-
  Systematically upgrade OpenClaw with pre-flight checks, changelog triage,
  local-patch preservation, and rollback support. Use when the user says
  "upgrade", "update", "bump version", "check for new version", "升级",
  "更新版本", "更新 OpenClaw", or references an UPDATE-GUIDE file. Also
  triggers on first install when the user says "初始化升级指南", "init
  update guide", or "scan openclaw environment".
---

# OC Update Guide Skill

帮助 agent 安全、系统地升级 OpenClaw，确保本地适配不被覆盖、升级有据可查、
出问题能回滚。

## 前置条件

本 skill 依赖一份项目级的 **UPDATE-GUIDE.md** 文件。

- **已有 UPDATE-GUIDE.md** → 直接进入「核心工作流」
- **首次使用 / 没有 UPDATE-GUIDE.md** → 先执行「首次初始化」自动生成

---

## 首次初始化

> 当项目中不存在 UPDATE-GUIDE.md，或用户明确要求初始化时执行。
> 全程自动，无需用户逐步确认。扫描完成后输出结果供用户审阅。

### 自动扫描

运行 `scripts/pre-upgrade-check.sh openclaw` 或手动执行以下检测：

```bash
# 版本
openclaw --version
npm list -g openclaw

# 安装路径
npm root -g  # → /usr/lib/node_modules，拼接 /openclaw

# 配置目录
ls ~/.openclaw/

# 工作目录（可能有多个 workspace-*）
ls -d ~/.openclaw/workspace*

# Patch 脚本
find ~/.openclaw/workspace*/patches/ -name "*.sh" -o -name "*.py" 2>/dev/null

# systemd 服务
systemctl --user list-units --type=service | grep openclaw

# 服务 ExecStartPre（查看自动 patch 入口）
systemctl --user cat openclaw-gateway.service 2>/dev/null | grep ExecStartPre
```

### 扫描检测项

| 检测项 | 采集方式 | 写入 UPDATE-GUIDE 字段 |
|--------|---------|----------------------|
| 当前版本 | `openclaw --version` | 基本信息 → 当前版本 |
| 安装路径 | `npm root -g`/openclaw | 基本信息 → 全局安装路径 |
| 配置文件 | `ls ~/.openclaw/*.json` | 基本信息 → 配置文件路径 |
| Patch 脚本 | `find` workspace patches | 本地 Patch 清单 |
| 手动修改 | 读取 patch 脚本内容，提取 sed/replace 操作 | 升级后需手动修复的文件 |
| systemd 服务名 | `systemctl --user list-units` | 基本信息 → 服务管理 |
| ExecStartPre | `systemctl --user cat` | 记录自动执行的 patch 入口 |
| 扩展/插件 | `ls ${install_path}/extensions/` | 已知升级陷阱（如 workspace:*） |
| 使用的 channel | 读取 openclaw.json 中的 channels 配置 | 功能关键词列表 |

### 生成 UPDATE-GUIDE.md

1. 读取 [oc-update-guide-template.md](oc-update-guide-template.md) 作为骨架
2. 用扫描结果填充所有字段
3. **Patch 清单需特别处理**：
   - 解析每个 patch 脚本，提取目标文件、匹配字符串、修改内容
   - 为每条 patch 生成验证命令（`grep -c "marker" target_file`）
   - 如果 patch 对应 GitHub Issue，在注释中提取 issue 编号
4. 从 openclaw.json 的 channels 配置提取关键词（如配置了 Telegram 就加入 `Telegram`）
5. 写入 UPDATE-GUIDE.md
6. **输出扫描报告**，展示所有检测到的内容，请用户审阅并补充遗漏

> 用户审阅后如有补充，直接修改 UPDATE-GUIDE.md 即可。

---

## 核心工作流

分 6 个阶段执行。大部分阶段连续自动运行，仅在两个关键决策点暂停等待用户确认。

### 确认策略

| 阶段 | 是否暂停 | 原因 |
|------|---------|------|
| Phase 1 读取配置 | ▶️ 自动 | 纯读取，无副作用 |
| Phase 2 版本筛选 | ⏸️ **暂停** | 用户需确认是否同意推荐版本 |
| Phase 3 备份 | ▶️ 自动 | 用户已在 Phase 2 确认，备份无破坏性 |
| Phase 4 执行升级 | ▶️ 自动 | 紧接备份，连续执行 |
| Phase 5 重打适配 | ▶️ 自动（失败时暂停） | 正常情况连续执行；patch 失败时暂停报告 |
| Phase 6 验证重启 | ⏸️ **暂停** | 展示最终验证结果，确认升级成功 |

> Agent 在每个阶段开始时输出 `[Phase N/6] 标题...` 进度提示，
> 让用户随时知道执行到了哪一步。

---

### Phase 1 — 读取 UPDATE-GUIDE（自动）

输出：`[Phase 1/6] 读取升级配置...`

1. 找到并读取 UPDATE-GUIDE.md
2. 提取关键信息：
   - `current_version` — 当前安装版本
   - `install_path` — 全局安装路径
   - `config_path` — 配置文件路径
   - `keywords` — 需搜索的功能关键词列表
   - `patches` — 本地 patch 清单（脚本路径、目标文件、验证命令）
   - `manual_fixes` — 需手动重做的修改清单
   - `known_traps` — 已知陷阱
3. 直接进入 Phase 2

### Phase 2 — Changelog 分析与版本推荐（⏸️ 暂停）

输出：`[Phase 2/6] 分析 changelog，筛选版本...`

1. 获取 changelog：
   ```bash
   less ${install_path}/CHANGELOG.md
   ```

2. 从 `current_version` 开始逐版本扫描，提取：
   - **Breaking Changes** — 逐条标注"影响/不影响"及理由
   - **Fixes** — 搜索 `keywords` 中的关键词，标记直接受益项
   - **Security** — 所有安全修复无条件标记
   - **已知问题** — 检查该版本的 GitHub Issues 有无回退报告

3. 版本筛选逻辑：

   | 条件 | 决策 |
   |------|------|
   | 含 beta / rc / canary 标签 | ❌ 跳过 |
   | 有直接受益的 bug fix | ✅ 候选 |
   | 有安全修复 | ✅ 强烈建议 |
   | 只有不相关的新功能 | ⏭️ 可跳过 |
   | 发布不足 3 天 | ⚠️ 等待，除非含紧急安全修复 |
   | 有已知回退 bug | ❌ 跳过，选更早的稳定版 |

4. **输出推荐报告并暂停**：

   ```
   ═══════════════════════════════════
   推荐版本: X.Y.Z
   升级理由:
   1. [受益修复1]（#issue）
   2. [受益修复2]（#issue）
   Breaking Change 确认: 无影响 / 需处理 XXX
   风险评估: 低/中/高
   ═══════════════════════════════════
   是否继续升级到此版本？
   ```

   等用户确认后进入 Phase 3。如用户拒绝或要求换版本，重新筛选。

### Phase 3 — 备份（自动）

输出：`[Phase 3/6] 备份配置...`

```bash
cp ${config_path} ${config_path}.bak.$(date +%Y%m%d)
echo "$(openclaw --version)" > /tmp/openclaw-pre-upgrade-version.txt
```

直接进入 Phase 4。

### Phase 4 — 执行升级（自动）

输出：`[Phase 4/6] 执行升级 → openclaw@${target_version}...`

```bash
npm i -g openclaw@${target_version}
openclaw doctor
```

直接进入 Phase 5。

### Phase 5 — 重打本地适配（自动，失败时暂停）

输出：`[Phase 5/6] 重打本地适配...`

#### 5a. 自动 Patch

```bash
bash ${patch_script_path}
```

逐条验证 patch 是否生效。**全部通过** → 继续；**任一失败** → 暂停并报告：

```
⚠️ Patch 验证失败：
- [patch名称]: 期望匹配 "xxx"，实际未找到
  目标文件: ${target_file}
  可能原因: 上游文件结构变化

建议操作:
1. 对比新旧版本差异
2. 更新 patch 匹配字符串
3. 重新运行
```

> Agent 尝试自动修复：对比新旧文件差异，定位新的匹配位置，更新 patch 脚本。
> 修复后重新验证。如果无法自动修复，暂停等待用户指示。

#### 5b. 手动修复

按 `manual_fixes` 清单逐项执行并验证。

#### 5c. 插件/扩展依赖修复

按 `known_traps` 中的已知问题逐项检查和修复。

### Phase 6 — 验证与重启（⏸️ 暂停）

输出：`[Phase 6/6] 重启服务，执行健康检查...`

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user restart openclaw-gateway.service

openclaw health
openclaw status
openclaw --version
```

**输出升级完成报告并暂停**：

```
═══════════════════════════════════
✅ 升级完成报告
版本: A.B.C → X.Y.Z
Patch 状态: 3/3 通过
手动修复: 2/2 完成
健康检查: 通过
═══════════════════════════════════
```

用户确认后，自动更新 UPDATE-GUIDE.md（见下方）。

---

## 回滚流程

任何阶段出现不可恢复的问题时：

```bash
OLD_VERSION=$(cat /tmp/openclaw-pre-upgrade-version.txt)
npm i -g openclaw@${OLD_VERSION}
openclaw doctor
cp ${config_path}.bak.* ${config_path}
bash ${patch_script_path}
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user restart openclaw-gateway.service
```

---

## 升级后更新 UPDATE-GUIDE

升级完成后，自动更新 UPDATE-GUIDE.md：

1. **版本信息** — `current_version` 改为新版本
2. **Breaking Changes 速查表** — 追加新版本的 breaking changes
3. **Patch 清单** — 如有 patch 更新，同步修改
4. **版本升级检查记录** — 覆盖为本次评估结论

---

## 安全守则

- **永远指定版本号**，不要用 `@latest`
- **先备份再升级**，不要跳过 Phase 3
- **逐条验证 patch**，不要假设 apply-patches.sh 一定成功
- **升级后立即做健康检查**，不要等到用户报错
- **保留回滚能力**，升级前记录旧版本号
