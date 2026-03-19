# Nanobot Agent Shell 交互与权限限制调查报告

## 1. Shell 交互工具: ExecTool

### 核心实现

**文件位置**: `nanobot/agent/tools/shell.py`

### 交互机制

```python
# shell.py:94-100
process = await asyncio.create_subprocess_shell(
    command,
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.PIPE,
    cwd=cwd,           # 工作目录
    env=env,           # 环境变量
)
```

**特点**:
- 使用 `asyncio.create_subprocess_shell()` 异步执行命令
- 支持自定义工作目录 (`working_dir`)
- 支持自定义超时 (默认 60s，最大 600s)
- 可扩展 PATH 环境变量 (`path_append`)
- 输出截断: 超过 10,000 字符时采用 "头+尾" 截断策略

---

## 2. 多层权限限制系统

### 2.1 危险命令拦截 (Deny Patterns)

```python
# shell.py:26-36
deny_patterns = [
    r"\brm\s+-[rf]{1,2}\b",          # rm -r, rm -rf, rm -fr
    r"\bdel\s+/[fq]\b",              # del /f, del /q
    r"\brmdir\s+/s\b",               # rmdir /s
    r"(?:^|[;&|]\s*)format\b",       # format
    r"\b(mkfs|diskpart)\b",          # 磁盘操作
    r"\bdd\s+if=",                   # dd
    r">\s*/dev/sd",                  # 写入磁盘
    r"\b(shutdown|reboot|poweroff)\b",  # 系统关机
    r":\(\)\s*\{.*\};\s*:",          # Fork Bomb
]
```

**拦截示例**:
```bash
rm -rf /          # ❌ 被拦截
dd if=/dev/zero   # ❌ 被拦截
format C:         # ❌ 被拦截
```

### 2.2 白名单模式 (Allow Patterns)

当配置了 `allow_patterns` 时，只有匹配白名单的命令才能执行：

```python
# shell.py:153-155
if self.allow_patterns:
    if not any(re.search(p, lower) for p in self.allow_patterns):
        return "Error: Command blocked by safety guard (not in allowlist)"
```

### 2.3 内部网络保护

```python
# shell.py:157-159
from nanobot.security.network import contains_internal_url
if contains_internal_url(cmd):
    return "Error: Command blocked by safety guard (internal/private URL detected)"
```

**保护范围**: 防止访问内网地址 (localhost, 192.168.x.x, 10.x.x.x 等)

### 2.4 工作目录限制 (Workspace Restriction)

```python
# shell.py:161-174
if self.restrict_to_workspace:
    if "..\\" in cmd or "../" in cmd:
        return "Error: Command blocked by safety guard (path traversal detected)"

    cwd_path = Path(cwd).resolve()
    for raw in self._extract_absolute_paths(cmd):
        p = Path(expanded).expanduser().resolve()
        if p.is_absolute() and cwd_path not in p.parents and p != cwd_path:
            return "Error: Command blocked by safety guard (path outside working dir)"
```

**限制效果**:
- 禁止路径遍历 (`../`, `..\`)
- 禁止访问工作目录外的绝对路径
- 支持 Windows (`C:\...`) 和 POSIX (`/home/...`) 路径检测

---

## 3. 文件系统工具权限

### 3.1 目录隔离机制

**文件位置**: `nanobot/agent/tools/filesystem.py`

```python
# filesystem.py:10-25
def _resolve_path(
    path: str,
    workspace: Path | None = None,
    allowed_dir: Path | None = None,
    extra_allowed_dirs: list[Path] | None = None,
) -> Path:
    p = Path(path).expanduser()
    if not p.is_absolute() and workspace:
        p = workspace / p
    resolved = p.resolve()
    if allowed_dir:
        all_dirs = [allowed_dir] + (extra_allowed_dirs or [])
        if not any(_is_under(resolved, d) for d in all_dirs):
            raise PermissionError(f"Path {path} is outside allowed directory")
    return resolved
```

### 3.2 文件工具列表

| 工具 | 功能 | 权限检查 |
|-----|------|---------|
| `read_file` | 读取文件内容 | ✓ 受 `allowed_dir` 限制 |
| `write_file` | 写入文件 | ✓ 受 `allowed_dir` 限制 |
| `edit_file` | 编辑文件 | ✓ 受 `allowed_dir` 限制 |
| `list_dir` | 列出目录 | ✓ 受 `allowed_dir` 限制 |

### 3.3 读取限制

```python
# filesystem.py:60-61
_MAX_CHARS = 128_000       # 最大返回字符数
_DEFAULT_LIMIT = 2000      # 默认读取行数
```

---

## 4. 配置方式

### 4.1 配置文件 (YAML)

```yaml
# ~/.nanobot/config.yaml
tools:
  exec:
    timeout: 120              # 默认超时 120 秒
    pathAppend: "/usr/local/bin:/opt/bin"

  restrictToWorkspace: true   # 启用工作目录限制
```

### 4.2 环境变量

```bash
# 超时设置
export NANOBOT_TOOLS__EXEC__TIMEOUT=120

# PATH 扩展
export NANOBOT_TOOLS__EXEC__PATH_APPEND="/usr/local/bin"

# 启用工作目录限制
export NANOBOT_TOOLS__RESTRICT_TO_WORKSPACE=true
```

### 4.3 配置 Schema

**文件位置**: `nanobot/config/schema.py:127-152`

```python
class ExecToolConfig(Base):
    """Shell exec tool configuration."""
    timeout: int = 60
    path_append: str = ""

class ToolsConfig(Base):
    web: WebToolsConfig = Field(default_factory=WebToolsConfig)
    exec: ExecToolConfig = Field(default_factory=ExecToolConfig)
    restrict_to_workspace: bool = False  # 全局目录限制
    mcp_servers: dict[str, MCPServerConfig] = Field(default_factory=dict)
```

---

## 5. 权限层级图

```
┌─────────────────────────────────────────────────────────────────┐
│                     Agent 权限限制层级                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Level 1: 危险命令拦截 (正则匹配)                        │   │
│  │  - rm -rf, dd, format, shutdown, fork bomb...           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           ↓ (通过)                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Level 2: 白名单检查 (如配置)                            │   │
│  │  - allow_patterns 必须匹配                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           ↓ (通过)                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Level 3: 网络安全检查                                   │   │
│  │  - 禁止访问内网/私有 IP                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           ↓ (通过)                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Level 4: 工作目录限制 (如启用)                          │   │
│  │  - 禁止 ../ 路径遍历                                     │   │
│  │  - 禁止访问工作目录外文件                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           ↓ (通过)                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Level 5: 系统调用执行                                   │   │
│  │  - asyncio.create_subprocess_shell()                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. 初始化流程

```python
# agent/loop.py:116-135
def _register_default_tools(self) -> None:
    """Register the default set of tools."""
    allowed_dir = self.workspace if self.restrict_to_workspace else None
    extra_read = [BUILTIN_SKILLS_DIR] if allowed_dir else None

    # 文件系统工具 (带目录限制)
    self.tools.register(ReadFileTool(workspace=self.workspace, allowed_dir=allowed_dir, ...))
    self.tools.register(WriteFileTool(workspace=self.workspace, allowed_dir=allowed_dir))
    ...

    # Shell 工具 (带限制配置)
    self.tools.register(ExecTool(
        working_dir=str(self.workspace),
        timeout=self.exec_config.timeout,
        restrict_to_workspace=self.restrict_to_workspace,
        path_append=self.exec_config.path_append,
    ))
```

---

## 7. 安全边界总结

| 限制类型 | 默认状态 | 配置方式 |
|---------|---------|---------|
| 危险命令拦截 | ✅ 始终启用 | 修改 `deny_patterns` |
| 白名单模式 | ❌ 默认关闭 | `allow_patterns` 参数 |
| 内网保护 | ✅ 始终启用 | `security/network.py` |
| 工作目录限制 | ❌ 默认关闭 | `restrict_to_workspace: true` |
| 超时限制 | 60秒 | `exec.timeout` (最大600秒) |
| 输出限制 | 10,000字符 | `_MAX_OUTPUT` 常量 |

---

## 8. 关键代码位置

| 功能 | 文件路径 | 行号 |
|-----|---------|-----|
| Shell 执行工具 | `nanobot/agent/tools/shell.py` | 1-184 |
| 文件系统工具 | `nanobot/agent/tools/filesystem.py` | 1-382 |
| 网络安全检查 | `nanobot/security/network.py` | (待查看) |
| 配置定义 | `nanobot/config/schema.py` | 127-152 |
| 工具注册 | `nanobot/agent/loop.py` | 116-135 |
