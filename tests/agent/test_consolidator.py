"""Tests for the lightweight Consolidator — append-only to HISTORY.md."""

import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

from nanobot.agent.memory import Consolidator, MemoryStore


@pytest.fixture
def store(tmp_path):
    return MemoryStore(tmp_path)


@pytest.fixture
def mock_provider():
    p = MagicMock()
    p.chat_with_retry = AsyncMock()
    return p


@pytest.fixture
def consolidator(store, mock_provider):
    sessions = MagicMock()
    sessions.save = MagicMock()
    return Consolidator(
        store=store,
        provider=mock_provider,
        model="test-model",
        sessions=sessions,
        context_window_tokens=1000,
        build_messages=MagicMock(return_value=[]),
        get_tool_definitions=MagicMock(return_value=[]),
        max_completion_tokens=100,
    )


class TestConsolidatorSummarize:
    async def test_summarize_appends_to_history(self, consolidator, mock_provider, store):
        """Consolidator should call LLM to summarize, then append to HISTORY.md."""
        mock_provider.chat_with_retry.return_value = MagicMock(
            content="User fixed a bug in the auth module."
        )
        messages = [
            {"role": "user", "content": "fix the auth bug"},
            {"role": "assistant", "content": "Done, fixed the race condition."},
        ]
        result = await consolidator.archive(messages)
        assert result is True
        entries = store.read_unprocessed_history(since_cursor=0)
        assert len(entries) == 1

    async def test_summarize_raw_dumps_on_llm_failure(self, consolidator, mock_provider, store):
        """On LLM failure, raw-dump messages to HISTORY.md."""
        mock_provider.chat_with_retry.side_effect = Exception("API error")
        messages = [{"role": "user", "content": "hello"}]
        result = await consolidator.archive(messages)
        assert result is True  # always succeeds
        entries = store.read_unprocessed_history(since_cursor=0)
        assert len(entries) == 1
        assert "[RAW]" in entries[0]["content"]

    async def test_summarize_skips_empty_messages(self, consolidator):
        result = await consolidator.archive([])
        assert result is False


class TestConsolidatorTokenBudget:
    async def test_prompt_below_threshold_does_not_consolidate(self, consolidator):
        """No consolidation when tokens are within budget."""
        session = MagicMock()
        session.last_consolidated = 0
        session.messages = [{"role": "user", "content": "hi"}]
        session.key = "test:key"
        consolidator.estimate_session_prompt_tokens = MagicMock(return_value=(100, "tiktoken"))
        consolidator.archive = AsyncMock(return_value=True)
        await consolidator.maybe_consolidate_by_tokens(session)
        consolidator.archive.assert_not_called()


class TestCompressSession:
    """Manual /compress vs automatic maybe_consolidate_by_tokens gates."""

    async def test_maybe_idle_between_target_and_budget_compress_runs(
        self, consolidator: Consolidator
    ) -> None:
        """Above half-budget target but below full budget: maybe skips, compress runs."""
        consolidator._SAFETY_BUFFER = 0
        consolidator.context_window_tokens = 200_000
        consolidator.max_completion_tokens = 100
        session = MagicMock()
        session.key = "test:key"
        session.last_consolidated = 0
        session.messages = [
            {"role": "user", "content": "u1"},
            {"role": "assistant", "content": "a1"},
        ]

        consolidator.estimate_session_prompt_tokens = MagicMock(return_value=(150_000, "tiktoken"))
        consolidator.pick_consolidation_boundary = MagicMock(return_value=(2, 100))
        consolidator.archive = AsyncMock(return_value=True)

        await consolidator.maybe_consolidate_by_tokens(session)
        consolidator.archive.assert_not_called()

        consolidator.estimate_session_prompt_tokens = MagicMock(
            side_effect=[(150_000, "tiktoken"), (40_000, "tiktoken")]
        )
        consolidator.archive.reset_mock()

        ok, msg = await consolidator.compress_session(session)
        assert ok is True
        consolidator.archive.assert_awaited_once()
        assert "150000" in msg and "40000" in msg

    async def test_compress_already_compact_skips_archive(self, consolidator: Consolidator) -> None:
        """At or below half-budget target: compress reports idle and does not archive."""
        consolidator._SAFETY_BUFFER = 0
        consolidator.context_window_tokens = 200_000
        consolidator.max_completion_tokens = 100
        session = MagicMock()
        session.key = "test:key"
        session.last_consolidated = 0
        session.messages = [{"role": "user", "content": "hi"}]

        consolidator.estimate_session_prompt_tokens = MagicMock(return_value=(50_000, "tiktoken"))
        consolidator.archive = AsyncMock(return_value=True)

        ok, msg = await consolidator.compress_session(session)
        assert ok is False
        assert "Already compact" in msg
        consolidator.archive.assert_not_called()
