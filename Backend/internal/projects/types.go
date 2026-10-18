package projects

import (
	"errors"
	"strings"

	"github.com/google/uuid"
)

type CreateProjectRequest struct {
	OrganizationID		uuid.UUID 		`json:"organizationID"`
	TeamID 				*uuid.UUID 		`json:"teamId,omitempty"`
	Name 				string 			`json:"name"`
	Slug 				string			`json:"slug"`
	Description 		*string			`json:"description,omitempty"`
	Visibility 			string 			`json:"visibility,omitempty"`    // public / team / private
}

func (req *CreateProjectRequest) Validate() error {
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

	if req.Description != nil {
		trimmed := strings.TrimSpace(*req.Description)
		req.Description = &trimmed
	}

	// Default visibility is team
	if req.Visibility == "" {
		req.Visibility = "team"
	}

	switch req.Visibility {
		case "public", "team", "private":
			// valid
		default:
			return errors.New("Visibility must be one of 'public', 'team' or 'private'")
	}

	return nil
}

type UpdateProjectRequest struct {
	Name 			*string 		`json:"name,omitempty"`
	Description 	*string 		`json:"description,omitempty"`
	Visibility 		*string 		`json:"visibility,omitempty"`
	TeamID 			*uuid.UUID 		`json:"teamId,omitempty"`
	IsArchived 		*bool 			`json:"isArchived,omitempty"`
}

func (req *UpdateProjectRequest) Validate() error {
	if req.Name != nil {
		trimmed := strings.TrimSpace(*req.Name)
		if trimmed == "" {
			return errors.New("project name cannot be empty")
		}
		req.Name = &trimmed
	}

	if req.Visibility != nil {
		switch *req.Visibility {
			case "public", "team", "private":
				// valid
			default:
				return errors.New("Visibility must be one of 'public', 'team' or 'private'")
		}
	}

	if req.Description != nil {
		trimmed := strings.TrimSpace(*req.Description)
		req.Description = &trimmed
	}

	return nil
}