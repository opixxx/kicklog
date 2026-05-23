package com.opixxx.kicklog.user.dto

import com.opixxx.kicklog.user.entity.User

data class UserSearchResponse(
    val users: List<Item>,
) {
    data class Item(
        val id: Long,
        val displayName: String,
    ) {
        companion object {
            fun from(user: User): Item = Item(id = user.id, displayName = user.displayName)
        }
    }

    companion object {
        fun from(users: List<User>): UserSearchResponse =
            UserSearchResponse(users = users.map(Item::from))
    }
}
