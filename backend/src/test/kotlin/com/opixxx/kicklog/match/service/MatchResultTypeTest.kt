package com.opixxx.kicklog.match.service

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * 매치 결과(승/무/패)는 클라이언트 입력이 아닌 팀 골 vs 상대 골로 백엔드에서 자동 derive 한다.
 *
 * 양쪽 골이 모두 입력된 경우에만 결과가 결정되며, 한 쪽이라도 null 이면 "모름" 상태로 null 반환.
 */
class MatchResultTypeTest {

    @Test
    fun `teamGoals 와 opponentGoals 모두 null 이면 null 을 반환한다`() {
        assertNull(MatchResultType.derive(teamGoals = null, opponentGoals = null))
    }

    @Test
    fun `teamGoals 만 null 이면 null 을 반환한다`() {
        assertNull(MatchResultType.derive(teamGoals = null, opponentGoals = 1))
    }

    @Test
    fun `opponentGoals 만 null 이면 null 을 반환한다`() {
        assertNull(MatchResultType.derive(teamGoals = 1, opponentGoals = null))
    }

    @Test
    fun `teamGoals 가 opponentGoals 보다 크면 WIN 을 반환한다`() {
        assertEquals(MatchResultType.WIN, MatchResultType.derive(teamGoals = 2, opponentGoals = 1))
    }

    @Test
    fun `teamGoals 가 opponentGoals 보다 작으면 LOSS 를 반환한다`() {
        assertEquals(MatchResultType.LOSS, MatchResultType.derive(teamGoals = 1, opponentGoals = 2))
    }

    @Test
    fun `teamGoals 와 opponentGoals 가 같으면 DRAW 를 반환한다`() {
        assertEquals(MatchResultType.DRAW, MatchResultType.derive(teamGoals = 1, opponentGoals = 1))
    }

    @Test
    fun `0대0 은 DRAW 를 반환한다`() {
        assertEquals(MatchResultType.DRAW, MatchResultType.derive(teamGoals = 0, opponentGoals = 0))
    }
}
