module QuickNotify

  module EventListener
    def self.included(base)
      base.extend ClassMethods
    end
    module ClassMethods

      def on_model(model, &block)
        QuickNotify.event_handlers << {
          model: model,
          action: nil,
          callback: block
        }
      end

      def on_action(action, &block)
        QuickNotify.event_handlers << {
          model: action[0, action.rindex('.')],
          action: action,
          callback: block
        }
      end

      def after_action(*actions, &block)
        actions.each do |action|
          QuickNotify.event_after_handlers << {
            action: action,
            callback: block
          }
        end
      end

    end
  end

end
