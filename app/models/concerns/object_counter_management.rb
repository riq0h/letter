# frozen_string_literal: true

module ObjectCounterManagement
  extend ActiveSupport::Concern

  class_methods do
    # 宣言的にオブジェクトカウンタを管理するコールバックを登録
    # 例: tracks_object_counter :favourites_count
    def tracks_object_counter(counter_name)
      after_create  :"increment_#{counter_name}"
      after_destroy :"decrement_#{counter_name}"

      define_method(:"increment_#{counter_name}") do
        ActivityPubObject.update_counters(object.id, counter_name => 1)
      end

      define_method(:"decrement_#{counter_name}") do
        ActivityPubObject.where(id: object.id).where("#{counter_name} > 0")
                         .update_all("#{counter_name} = #{counter_name} - 1")
      end

      private :"increment_#{counter_name}", :"decrement_#{counter_name}"
    end
  end
end
