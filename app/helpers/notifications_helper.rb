module NotificationsHelper
  def event_notification_title(event)
    case event_notification_action(event)
    when "comment_created" then "RE: #{card_notification_title(event.eventable.card)}"
    else card_notification_title(event.eventable)
    end
  end

  def event_notification_body(event)
    name = event.creator.name

    case event_notification_action(event)
    when "card_closed"
      if event.card.closure
        "Closed as “#{event.card.closure.reason}” by #{name}"
      else
        "Closed by #{name}"
      end
    when "card_reopened" then "Reopened by #{name}"
    when "card_published" then "Added by #{name}"
    when "comment_created" then comment_notification_body(event)
    when "card_assigned" then "Assigned to #{event.assignees.none? ? "self" : event.assignees.pluck(:name).to_sentence}"
    else name
    end
  end

  def notification_tag(notification, &)
    tag.div id: dom_id(notification), class: "tray__item tray__item--notification", data: { navigable_list_target: "item" } do
      concat(
        link_to(notification,
          class: [ "card card--notification", { "card--closed": notification.card.closed? }, { "unread": !notification.read? } ],
          data: { turbo_frame: "_top", badge_target: "unread", action: "badge#update" },
          style: { "--card-color:": notification.card.color },
          &)
      )
    end
  end

  def notification_toggle_read_button(notification)
    if notification.read?
      button_to read_notification_path(notification),
          method: :delete,
          class: "card__notification-unread-indicator btn btn--circle borderless",
          title: "Mark as unread",
          data: { action: "form#submit:stop badge#update:stop", form_target: "submit" },
          form: { data: { controller: "form" } } do
        concat(icon_tag("unseen"))
        concat(tag.span("Mark as unread", class: "for-screen-reader"))
      end
    else
      button_to read_notification_path(notification),
          class: "card__notification-unread-indicator btn btn--circle borderless",
          title: "Mark as read",
          data: { action: "form#submit:stop badge#update:stop", form_target: "submit" },
          form: { data: { controller: "form" } } do
        concat(icon_tag("remove-med"))
        concat(tag.span("Mark as read", class: "for-screen-reader"))
      end
    end
  end

  def notifications_next_page_link(page)
    unless @page.last?
      tag.div id: "next_page", data: { controller: "fetch-on-visible", fetch_on_visible_url_value: notifications_path(page: @page.next_param) }
    end
  end

  private
    def event_notification_action(event)
      if event.action.card_published? && event.eventable.assigned_to?(event.creator)
        "card_assigned"
      else
        event.action
      end
    end

    def comment_notification_body(event)
      comment = event.eventable
      strip_tags(comment.body.to_s).truncate(200)
    end

    def card_notification_title(card)
      card.title.presence || "Card #{card.id}"
    end
end
