# Nanobot 上下文/会话管理策略调查报告

## 概述

本文档分析了 nanobot 项目的对话上下文管理机制，包括会话存储、滑动窗口限制和自动压缩总结策略。

---

## 1. 滑动窗口限制

### 双层级限制

| 限制类型 | 默认值 | 代码位置 |
|---------|-------|---------|
| 消息数量限制 | 500 条 | `session/manager.py:69` |
| Token 限制 | 65,536 (64K) | `config/schema.py:38` |

### 关键代码

```python
# session/manager.py:69-72
def get_history(self, max_messages: int = 500) -> list[dict[str, Any]]:
    unconsolidated = self.messages[self.last_consolidated:]
    sliced = unconsolidated[-max_messages:]
```

```python
# config/schema.py:38
context_window_tokens: int = 65_536
```

---

## 2. 自压缩和总结机制

### 核心组件: MemoryConsolidator

**文件位置**: `agent/memory.py:222-358`

### 触发条件

当估计的 prompt tokens 超过 `context_window_tokens` 时触发压缩：

```python
# agent/memory.py:309-321
target = self.context_window_tokens // 2  # 目标：压缩到 50%
estimated, source = self.estimate_session_prompt_tokens(session)
if estimated < self.context_window_tokens:
    return  # 无需压缩
```

### 压缩流程

```
┌─────────────────────────────────────────────────────────────┐
│                    压缩流程 (最多 5 轮)                      │
├─────────────────────────────────────────────────────────────┤
│  1. 估计当前 prompt tokens                                  │
│     ↓                                                       │
│  2. 选择用户消息边界 (pick_consolidation_boundary)          │
│     ↓                                                       │
│  3. LLM 生成摘要 (save_memory 工具调用)                     │
│     ↓                                                       │
│  4. 更新 last_consolidated 偏移量                           │
│     ↓                                                       │
│  5. 重复直到低于目标或达到最大轮次                          │
└─────────────────────────────────────────────────────────────┘
```

### 摘要存储结构

**save_memory 工具输出**:
- `history_entry`: 写入 `HISTORY.md` 的时间戳摘要条目
  - 格式: `[YYYY-MM-DD HH:MM] 摘要内容`
- `memory_update`: 更新 `MEMORY.md` 的完整长期记忆

```python
# agent/memory.py:125-136
chat_messages = [
    {"role": "system", "content": "You are a memory consolidation agent..."},
    {"role": "user", "content": prompt},  # 包含当前记忆和待处理对话
]
```

### 失败回退机制

```python
# agent/memory.py:78, 201-219
_MAX_FAILURES_BEFORE_RAW_ARCHIVE = 3

def _fail_or_raw_archive(self, messages: list[dict]) -> bool:
    self._consecutive_failures += 1
    if self._consecutive_failures < self._MAX_FAILURES_BEFORE_RAW_ARCHIVE:
        return False
    self._raw_archive(messages)  # 直接转储原始消息
```

---

## 3. 工具调用完整性保护

### _find_legal_start()

**文件位置**: `session/manager.py:47-67`

**作用**: 防止滑动窗口切掉 `tool_call` 但保留 `tool result` 导致的孤儿问题。

**算法**:
1. 跟踪所有 assistant 消息中声明的 `tool_call_id`
2. 如果遇到没有对应声明的 tool result，跳过该消息
3. 确保窗口起始位置在合法边界

```python
# session/manager.py:80-84
# 注释说明
# Some providers reject orphan tool results if the matching assistant
# tool_calls message fell outside the fixed-size history window.
start = self._find_legal_start(sliced)
if start:
    sliced = sliced[start:]
```

---

## 4. 双层记忆存储架构

```
┌──────────────────────────────────────────────────────────────┐
│                        记忆存储层级                           │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐    JSONL 格式    ┌─────────────────────┐   │
│  │  活跃会话    │ ◄──────────────► │  sessions/*.jsonl   │   │
│  │  (内存中)    │                  │  (持久化存储)        │   │
│  └─────────────┘                  └─────────────────────┘   │
│         │                                                    │
│         │ last_consolidated 偏移量                           │
│         ▼                                                    │
│  ┌─────────────┐    LLM 总结      ┌─────────────────────┐   │
│  │  待归档消息  │ ───────────────► │    MEMORY.md        │   │
│  │  (未压缩)    │                  │  (长期结构化记忆)     │   │
│  └─────────────┘                  ├─────────────────────┤   │
│                                   │    HISTORY.md       │   │
│                                   │  (时间线日志/grep)   │   │
│                                   └─────────────────────┘   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Session 数据结构

```python
# session/manager.py:16-33
@dataclass
class Session:
    key: str  # channel:chat_id
    messages: list[dict[str, Any]] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.now)
    updated_at: datetime = field(default_factory=datetime.now)
    metadata: dict[str, Any] = field(default_factory=dict)
    last_consolidated: int = 0  # 已归档消息数
```

---

## 5. Token 估算策略

### 估算方法优先级

1. **Provider 计数器** (如果可用)
2. **tiktoken 回退** (cl100k_base 编码)

```python
# utils/helpers.py:159-177
def estimate_prompt_tokens_chain(...):
    # 优先使用 provider 的计数器
    provider_counter = getattr(provider, "estimate_prompt_tokens", None)
    if provider_counter:
        tokens, source = provider_counter(messages, tools, model)
        if tokens > 0:
            return int(tokens), str(source or "provider_counter")

    # 回退到 tiktoken
    estimated = estimate_prompt_tokens(messages, tools)
    return int(estimated), "tiktoken"
```

### 消息 Token 估算

```python
# utils/helpers.py:125-134
def estimate_message_tokens(message: dict[str, Any]) -> int:
    base = 4  # 每条消息基础开销
    content = message.get("content", "")
    if isinstance(content, str):
        return base + len(content) // 4
    # 处理多模态内容...
```

---

## 6. 关键代码位置汇总

| 功能 | 文件路径 | 行号 |
|-----|---------|-----|
| Session 管理 | `nanobot/session/manager.py` | 1-243 |
| 内存压缩逻辑 | `nanobot/agent/memory.py` | 114-358 |
| Token 估算 | `nanobot/utils/helpers.py` | 100-177 |
| 配置项 | `nanobot/config/schema.py` | 29-48 |
| 压缩触发点 | `nanobot/agent/loop.py` | 370, 383, 417, 449 |

---

## 7. 配置调整

在配置文件中修改上下文窗口大小：

```yaml
# config.yaml
agents:
  defaults:
    contextWindowTokens: 131072  # 128K tokens
    maxTokens: 16384
```

或通过环境变量：

```bash
export NANOBOT_AGENTS__DEFAULTS__CONTEXT_WINDOW_TOKENS=131072
```

---

## 8. 总结

Nanobot 采用了一套完整的上下文管理策略：

1. **预防性压缩**: 在达到硬限制前主动压缩，避免 LLM 调用失败
2. **智能边界**: 以用户消息为边界，保证工具调用链完整性
3. **LLM 驱动总结**: 利用 LLM 生成高质量摘要，而非简单截断
4. **多层存储**: 活跃会话 → 摘要归档 → 原始日志，各层职责清晰
5. **失败容错**: LLM 总结失败时有原始消息回退机制
