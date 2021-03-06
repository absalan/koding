package models

import (
	"errors"
	"socialapi/models"

	// "fmt"
	"time"

	"github.com/hashicorp/go-multierror"
	"github.com/koding/bongo"
)

type NotificationContent struct {
	// unique identifier of NotificationContent
	Id int64 `json:"id"`

	// target of the activity (replied messageId, followed accountId etc.)
	TargetId int64 `json:"targetId,string"   sql:"NOT NULL"`

	// Type of the NotificationContent
	TypeConstant string `json:"typeConstant" sql:"NOT NULL;TYPE:VARCHAR(100);"`

	// Creation date of the NotificationContent
	CreatedAt time.Time `json:"createdAt"`
}

const (
	// NotificationContent Types
	NotificationContent_TYPE_LIKE    = "like"
	NotificationContent_TYPE_COMMENT = "comment"
	NotificationContent_TYPE_MENTION = "mention"
	NotificationContent_TYPE_PM      = "chat"
)

func (n *NotificationContent) FindByTarget() error {
	s := map[string]interface{}{
		"type_constant": n.TypeConstant,
		"target_id":     n.TargetId,
	}
	q := bongo.NewQS(s)

	return n.One(q)
}

// CreateNotification validates notifier instance and creates a new notification
// with actor activity.
func CreateNotificationContent(i Notifier) (*NotificationContent, error) {
	// first check for type constant and target id
	if i.GetType() == "" {
		return nil, errors.New("Type must be set")
	}

	if i.GetTargetId() == 0 {
		return nil, errors.New("TargetId must be set")
	}

	if i.GetActorId() == 0 {
		return nil, errors.New("ActorId must be set")
	}

	nc, err := ensureNotificationContent(i)
	if err != nil {
		return nil, err
	}

	a := NewNotificationActivity()
	a.NotificationContentId = nc.Id
	a.ActorId = i.GetActorId()
	a.MessageId = i.GetMessageId()

	if err := a.Create(); err != nil {
		return nil, err
	}

	return nc, nil
}

// ensureNotificationContent adds caching layer on top of notification content fetching
func ensureNotificationContent(i Notifier) (*NotificationContent, error) {
	// check for previous NotificationContent create if it does not exist (type:comment targetId:messageId)
	nc, err := Cache.NotificationContent.ByTypeConstantAndTargetID(i.GetType(), i.GetTargetId())
	if err == nil {
		return nc, nil
	}

	nc = NewNotificationContent()
	nc.TypeConstant = i.GetType()
	nc.TargetId = i.GetTargetId()
	if err := nc.Create(); err != nil {
		return nil, err
	}

	// after creating the notificationcontent we can set it to cache for future
	// usage
	if err := Cache.NotificationContent.SetToCache(nc); err != nil {
		return nil, err
	}

	return nc, nil
}

// FetchByIds fetches notification contents with given ids
func (n *NotificationContent) FetchByIds(ids []int64) ([]NotificationContent, error) {
	notificationContents := make([]NotificationContent, 0)
	if err := bongo.B.FetchByIds(n, &notificationContents, ids); err != nil {
		return nil, err
	}
	return notificationContents, nil
}

// FetchMapByIds returns NotificationContent map with given ids
func (n *NotificationContent) FetchMapByIds(ids []int64) (map[int64]NotificationContent, error) {
	ncList, err := n.FetchByIds(ids)
	if err != nil {
		return nil, err
	}

	ncMap := make(map[int64]NotificationContent, 0)
	for _, nc := range ncList {
		ncMap[nc.Id] = nc
	}

	return ncMap, nil
}

func (n *NotificationContent) FetchIdsByTargetId(targetId int64) ([]int64, error) {
	var ids []int64

	query := &bongo.Query{
		Selector: map[string]interface{}{
			"target_id": targetId,
		},
		Pluck: "id",
	}

	return ids, n.Some(&ids, query)
}

// CreateNotificationType creates an instance of notifier subclasses
func CreateNotificationContentType(notificationType string) (Notifier, error) {
	switch notificationType {
	case NotificationContent_TYPE_LIKE:
		return NewInteractionNotification(notificationType), nil
	case NotificationContent_TYPE_COMMENT:
		return NewReplyNotification(), nil
	case NotificationContent_TYPE_MENTION:
		return NewMentionNotification(), nil
	default:
		return nil, errors.New("undefined notification type")
	}

}

func (n *NotificationContent) GetContentType() (Notifier, error) {
	return CreateNotificationContentType(n.TypeConstant)
}

func (n *NotificationContent) GetDefinition() string {
	nt, err := CreateNotificationContentType(n.TypeConstant)
	if err != nil {
		return ""
	}

	return nt.GetDefinition()
}

// DeleteByIds deletes the given id of NotificationContent (same with content id)
func (n *NotificationContent) DeleteByIds(ids ...int64) error {
	// we use error struct for this function because of iterating over all elements
	// and we'r gonna try to delete given ids at least one time..
	var errs *multierror.Error

	if len(ids) == 0 {
		return models.ErrIdIsNotSet
	}

	for _, id := range ids {
		nc := NewNotificationContent()
		if err := nc.ById(id); err != nil {
			// our aim is removing data from DB
			// so if record is not found in database
			// we can ignore this RecordNotFound error
			if err != bongo.RecordNotFound {
				errs = multierror.Append(errs, err)
			}
		}

		if err := nc.Delete(); err != nil {
			if err != bongo.RecordNotFound {
				errs = multierror.Append(errs, err)
			}
		}

	}

	return errs.ErrorOrNil()
}
