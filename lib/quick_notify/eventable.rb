module QuickNotify
  module Eventable

    def save_event(action, model, opts={})
      AppEvent.add(action, model, self.current_user, opts)
    end

    def publish_event(action, model, publisher, opts={})
      AppEvent.publish(action, model, self.current_user, publisher, opts)
    end

  end
end
