package com.sanvya.app.domain.repository

interface PushRepository {
    suspend fun registerToken(token: String, platform: String, userId: String)
}
