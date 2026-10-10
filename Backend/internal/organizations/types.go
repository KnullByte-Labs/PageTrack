package organizations

import (
	"errors"
	"strings"
)

type CreateOrganizationRequest struct {
	Name        string  `json:"name"`
	Slug        string  `json:"slug"`
	DisplayName *string `json:"displayName,omitempty"`
	ImageUrl    *string `json:"imageUrl,omitempty"`
	LiveUrl     *string `json:"liveUrl,omitempty"`
	Description *string `json:"description,omitempty"`
}

func (req *CreateOrganizationRequest) Validate() error {
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

type UpdateOrganizationRequest struct {
	Name        *string `json:"name,omitempty"`
	DisplayName *string `json:"displayName,omitempty"`
	ImageUrl    *string `json:"imageUrl,omitempty"`
	LiveUrl     *string `json:"liveUrl,omitempty"`
	Description *string `json:"description,omitempty"`
}

func (req *UpdateOrganizationRequest) Validate() error {
	if req.Name != nil {
		trimmed := strings.TrimSpace(*req.Name)

		if trimmed == "" {
			return errors.New("name cannot be empty")
		}

		req.Name = &trimmed
	}

	return nil
}
