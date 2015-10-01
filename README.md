# QuickNotify

QuickNotify is a flexible notification library built for Ruby On Rails. It provides for the sending of notifications over e-mail, push notifications, etc. Currently this library only works with MongoDB, and depends on the QuickJob library.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'quick_notify', github: 'agquick/quick_notify'
gem 'mongo_helper', github: 'agquick/mongo_helper'
gem 'quick_jobs', github: 'agquick/quick_jobs'
```

And then execute:

```term
$ bundle install
```

---

## Usage

QuickNotify is built on the assumption that (almost) every notification is generated from an event. Therefore, a keystone to this notification library is the `AppEvent` model. Below is a guide to setting up your application to generate and send notifications derived from events.

### Defining Your Event Model

The `Event` model simply defines what happens when a particular event occurs. It also allows you to ensure certain actions are performed in the background.

Define your own model by including the `QuickNotify::Event` module in new class your `models` directory (let's call it `AppEvent`). Here you can define what happens when a event is processed.

```ruby
class AppEvent
	include Mongoid::Document
	include QuickNotify::Event

	quick_notify_event_keys_for!(:mongoid)

	on_model 'comment' do |e|
		comment = e.model
		post	= comment.model
		user = comment.actor

		e.meta['post'] = frame.to_api(:min) unless frame.nil?
	end

	on_action 'comment.created' do |e|
		# This is ran when the event has been fully processed by all other hooks,
		# and all metadata has been added and saved.
		e.run lambda {|pe|
			com = pe.model
			post = com.post
			Job.run_later(:meta, post, :register_activity!)
			# Here we will send a notification
			Job.run_later(:notification, Notification, :add_for_event, [pe.id.to_s])
		}
	end
end
```

### Defining Your Notification Model

The `Notification` module provides the functionality for storing and sending a message over a platform of your choice. Presently the platforms supported are iOS push notifications and email, but others can be easily added.

```ruby
class Notification
	include Mongoid::Document
	include QuickNotify::Notification

	quick_notify_notification_keys_for(:mongoid)

	def self.add_for_event(event_id)
		ev = AppEvent.find(event_id)
		publisher = ev.publisher

		recipients = []
		if publisher.is_a? Post
			recipients = publisher.editors	# list of users tied to post
		end

		recipients.each do |user|
			cfg = self.config_for_event(ev, user)
			notif = Notification.add(user, :event, {
				event: ev,
				subject: cfg[:subject] || "App Notification",
				message: cfg[:message],
				full_message: cfg[:full_message] || cfg[:message],
				html_message: cfg[:html_message],
				delivery_platforms: cfg[:delivery_platforms] || [:email]
			})
			notif.deliver
		end
	end

	def self.config_for_event(event, user)
		cfg = {}
		case ev.action
		when 'comment.created'
			comment = event.model
			actor_name = event.actor.name
			post_title = comment.post.title
			cfg[:message] = "#{actor_name} added a comment to #{post_title}."
			cfg[:subject] = "Comment added!"
		end
		return cfg
	end

end
```

### Publishing Events

Once your event and notification models are defined, you are ready to publish events.

```ruby
class Comment
	...

	def register!(opts)
		# create comment stuff here...

		AppEvent.publish("comment.created", {model: self, actor: self.creator, publisher: self.post, meta: {})

	end

end
```

### Setup Configuration

Finally, ensure your settings are configured properly in quick_notify.yml

```yaml
development:
	classes:
		event: AppEvent
		device: Device
	apns:
		host: gateway.sandbox.push.apple.com
		port: 2195
		pem: certs/blog_apn_development.pem
	email:
		from: 'MyBlog <mailer@myblog.com>'
		authentication: :plain
		address: smtp.mailgun.org
		port: 587
		domain: myblog.com
		user_name: postmaster@myblog.com
		password: abc123
		html_layout: 'email.html.erb'
```

---

## API

### Event

#### Class Methods

**on_model(model_string) do |event|**

Declare action on certain event. The model should be the first part of the action string up to the period.

**on_action(action) do |event|**

Declare action on certain event

**on_all do |event|**

Perform certain action on all events

**publish(action, model, user, publisher, metadata={})**

Publish an event

**publish(action, opts)**

Alternate method of publishing event

#### Properties

**action**

The action that occurred. It should have the form of {lowercase model name}.{lowercase action} (e.g. 'comment.created').

**actor**

The object that committed the action (typically a User instance)

**model**

The model that was modified (can be any model in your app)

**publisher**

The model that best encapsulates the scope of the event (for a Comment, it may be the Post the comment belongs to)

**meta**

A hash of additional data to be stored with the event.

### Notification

#### Class Methods

**add(user, action, options)**

Add notification for user with action.

---

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
