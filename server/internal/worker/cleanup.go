package worker

import (
	"context"
	"log"
	"time"

	"bimstreaming/server/internal/repository"
)

func StartCleanupLoop(ctx context.Context, repo *repository.Repository) {
	go dailyCleanupLoop(ctx, repo)
	go statusExpiryLoop(ctx, repo)
}

func dailyCleanupLoop(ctx context.Context, repo *repository.Repository) {
	for {
		next := nextDailyRunUTC(time.Now().UTC())
		timer := time.NewTimer(time.Until(next))
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
			RunDailyCleanup(ctx, repo)
		}
	}
}

func statusExpiryLoop(ctx context.Context, repo *repository.Repository) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := repo.CleanupExpiredStatuses(ctx); err != nil {
				log.Printf("cleanup expired statuses: %v", err)
			}
		}
	}
}

func RunDailyCleanup(ctx context.Context, repo *repository.Repository) {
	now := time.Now().UTC()
	if err := repo.CleanupExpiredAuthTokens(ctx); err != nil {
		log.Printf("cleanup expired auth tokens: %v", err)
	}
	if err := repo.CleanupExpiredEmailVerificationTokens(ctx); err != nil {
		log.Printf("cleanup email verification tokens: %v", err)
	}
	if err := repo.CleanupExpiredPasswordResetTokens(ctx); err != nil {
		log.Printf("cleanup password reset tokens: %v", err)
	}
	if err := repo.CleanupExpiredRemoteSessionInvites(ctx); err != nil {
		log.Printf("cleanup remote invites: %v", err)
	}
	if err := repo.CleanupOldLoginHistory(ctx, now.Add(-90*24*time.Hour)); err != nil {
		log.Printf("cleanup old login history: %v", err)
	}
	if err := repo.CleanupSoftDeletedMessages(ctx, now.Add(-30*24*time.Hour)); err != nil {
		log.Printf("cleanup soft deleted messages: %v", err)
	}
	if err := repo.CleanupExpiredStatuses(ctx); err != nil {
		log.Printf("cleanup expired statuses: %v", err)
	}
}

func nextDailyRunUTC(now time.Time) time.Time {
	run := time.Date(now.Year(), now.Month(), now.Day(), 3, 0, 0, 0, time.UTC)
	if !now.Before(run) {
		run = run.Add(24 * time.Hour)
	}
	return run
}
