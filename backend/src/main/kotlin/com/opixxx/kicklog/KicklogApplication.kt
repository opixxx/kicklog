package com.opixxx.kicklog

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class KicklogApplication

fun main(args: Array<String>) {
	runApplication<KicklogApplication>(*args)
}
