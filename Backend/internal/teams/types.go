package teams

import (
	"errors"
	"strings"

	"github.com/google/uuid"
)

type CreateTeamRequest struct {
	OrganizationID 	uuid.UUID 	`json:"organizationId"`
	Name			string		`json:"name"`
	Slug			string 		`json:"slug"`
	IDPGroupPath 	*string 	`json:"idpGroupPath,omitempty"`
}

func (req *CreateTeamRequest) Validate() error {
	if req.OrganizationID == uuid.Nil {
		return errors.New("organizationID is required")
	}
	req.Name = strings.TrimSpace(req.Name)
	req.Slug = strings.TrimSpace(strings.ToLower(req.Slug))

	if req.Name == "" {
		return errors.New("name is required")
	}

	if req.Slug == "" {
		return errors.New("slug is required")
	}

	return nil
}

type UpdateTeamRequest struct {
	Name 			*string 	`json:"name,omitempty"`
	IDPGroupPath 	*string 	`json:"idpGroupPath,omitempty"`
}

func (req *UpdateTeamRequest) Validate() error {
	if req.Name != nil {
		trimmed := strings.TrimSpace(*req.Name)
		if trimmed == "" {
			return errors.New("name cannot be empty")
		}

		req.Name = &trimmed
	}

	return nil
}

type GetTeamBySlug struct {
	OrganizationID 	uuid.UUID 	`json:"organizationId"`
	Slug			string 		`json:"slug"`
}