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
