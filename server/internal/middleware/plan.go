package middleware

import (
	"net/http"
	"strings"

	"bimstreaming/server/internal/models"
	"bimstreaming/server/internal/repository"

	"github.com/google/uuid"
)

type PlanEnforcer struct {
	repo *repository.Repository
}

func NewPlanEnforcer(repo *repository.Repository) *PlanEnforcer {
	return &PlanEnforcer{repo: repo}
}

func (p *PlanEnforcer) RequireFeature(feature string) func(http.Handler) http.Handler {
	return p.require(func(plan *models.Plan, _ uuid.UUID, _ *http.Request) error {
		if !planAllowsFeature(plan, feature) {
			return errPlanDenied
		}
		return nil
	})
}

func (p *PlanEnforcer) RequireMaxCommunities() func(http.Handler) http.Handler {
	return p.require(func(plan *models.Plan, userID uuid.UUID, r *http.Request) error {
		if plan == nil || !plan.MaxCommunities.Valid || plan.MaxCommunities.Int32 <= 0 {
			return errPlanDenied
		}
		count, err := p.repo.CountUserCommunities(r.Context(), userID)
		if err != nil {
			return err
		}
		if count >= int(plan.MaxCommunities.Int32) {
			return errPlanDenied
		}
		return nil
	})
}

func (p *PlanEnforcer) RequireMaxConcurrentSessions() func(http.Handler) http.Handler {
	return p.require(func(plan *models.Plan, userID uuid.UUID, r *http.Request) error {
		if plan == nil || !plan.MaxConcurrentSessions.Valid || plan.MaxConcurrentSessions.Int32 <= 0 {
			return errPlanDenied
		}
		count, err := p.repo.CountActiveRemoteSessions(r.Context(), userID)
		if err != nil {
			return err
		}
		if count >= int(plan.MaxConcurrentSessions.Int32) {
			return errPlanDenied
		}
		return nil
	})
}

var errPlanDenied = planError("plan limit reached")

type planError string

func (e planError) Error() string { return string(e) }

func (p *PlanEnforcer) require(check func(*models.Plan, uuid.UUID, *http.Request) error) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims, ok := ClaimsFromContext(r.Context())
			if !ok {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			userID, err := uuid.Parse(claims.RegisteredClaims.Subject)
			if err != nil {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			plan, err := p.repo.GetEffectivePlanForUser(r.Context(), userID)
			if err != nil {
				http.Error(w, "failed to evaluate plan", http.StatusInternalServerError)
				return
			}
			if err := check(plan, userID, r); err != nil {
				if err == errPlanDenied {
					http.Error(w, "plan limit reached", http.StatusForbidden)
					return
				}
				http.Error(w, "failed to evaluate plan", http.StatusInternalServerError)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func planAllowsFeature(plan *models.Plan, feature string) bool {
	if plan == nil {
		return false
	}
	feature = strings.TrimSpace(strings.ToLower(feature))
	switch feature {
	case "unattended_access":
		return plan.UnattendedAccess
	case "session_recording":
		return plan.SessionRecording
	case "priority_support":
		return plan.PrioritySupport
	case "custom_alias":
		return plan.CustomAlias
	default:
		return true
	}
}
