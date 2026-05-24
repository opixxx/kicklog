package com.opixxx.kicklog.testsupport

import com.opixxx.kicklog.friend.entity.Friendship
import com.opixxx.kicklog.friend.repository.FriendshipStore
import com.opixxx.kicklog.match.service.MatchPosition
import com.opixxx.kicklog.match.service.MatchResultType
import com.opixxx.kicklog.match.service.UpsertMatchCommand
import com.opixxx.kicklog.match.service.UpsertQuarterCommand
import com.opixxx.kicklog.user.entity.User
import com.opixxx.kicklog.user.repository.UserStore
import com.opixxx.kicklog.venue.entity.Venue
import com.opixxx.kicklog.venue.repository.VenueStore
import java.math.BigDecimal
import java.time.Instant

object ServiceTestFixtures {
    fun saveVenue(venueRepository: VenueStore, userId: Long, namePrefix: String = "테스트운동장"): Venue {
        return venueRepository.save(
            Venue.create(
                userId = userId,
                name = "$namePrefix-$userId",
                geoLat = BigDecimal("37.668100"),
                geoLng = BigDecimal("126.799200"),
                address = null,
                roadAddress = null,
                provider = "kakao",
                providerPlaceId = "$namePrefix-place-$userId",
            ),
        )
    }

    fun saveUser(userRepository: UserStore, displayName: String): User {
        return userRepository.save(User.create(displayName = displayName, email = "$displayName@example.com"))
    }

    fun saveAcceptedFriendship(friendshipRepository: FriendshipStore, userId: Long, targetUserId: Long) {
        val now = Instant.parse("2026-05-23T09:00:00Z")
        val friendship = Friendship.createPending(userId, targetUserId, now)
        friendship.accept(now)
        friendshipRepository.save(friendship)
    }

    fun matchCommand(
        venueId: Long,
        playedAt: String = "2026-05-23T09:00:00Z",
        goals: Int = 1,
        assists: Int = 0,
        workoutId: String = "hk-uuid-1",
        distanceM: Int = 0,
        maxSpeedKmh: Double = 0.0,
        sprintCount: Int = 0,
        avgHeartRate: Int = 0,
    ): UpsertMatchCommand {
        val instant = Instant.parse(playedAt)
        return UpsertMatchCommand(
            venueId = venueId,
            playedAt = instant,
            opponent = "OO FC",
            result = MatchResultType.WIN,
            position = MatchPosition.MF,
            goals = goals,
            assists = assists,
            totalDistanceM = distanceM,
            maxSpeedKmh = maxSpeedKmh,
            sprintCount = sprintCount,
            avgHeartRate = avgHeartRate,
            quarters = listOf(metricQuarter(instant, workoutId, distanceM, sprintCount)),
        )
    }

    private fun metricQuarter(
        startedAt: Instant,
        workoutId: String,
        distanceM: Int,
        sprintCount: Int,
    ): UpsertQuarterCommand {
        return UpsertQuarterCommand(
            quarterNumber = 1,
            healthKitWorkoutId = workoutId,
            startedAt = startedAt,
            endedAt = startedAt.plusSeconds(900),
            durationSeconds = 900,
            distanceM = distanceM,
            avgSpeedKmh = 6.1,
            avgHeartRate = 145,
            maxHeartRate = 160,
            sprintCount = sprintCount,
            activeEnergyKcal = 120,
        )
    }
}
