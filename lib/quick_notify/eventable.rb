module QuickNotify
  module Eventable

    def save_event(action, model, opts={})
      AppEvent.add(action, model, self.current_user, opts)
    end

  end
end
