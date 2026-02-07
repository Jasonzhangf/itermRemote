package main

import (
	"context"
	"github.com/redis/go-redis/v9"
)

var redisClient *redis.Client
var ctx = context.Background()

func initRedis() *redis.Client {
	redisClient = redis.NewClient(&redis.Options{
		Addr:     getEnv("REDIS_HOST", "localhost") + ":" + getEnv("REDIS_PORT", "6379"),
		Password: getEnv("REDIS_PASSWORD", ""),
		DB:       0,
	})
	return redisClient
}
