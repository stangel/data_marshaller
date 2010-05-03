module DataMarshaller
  module ClassMethods
    @@marshaled_columns ||= {}
    def marshaled_columns(columns_to_marshal=nil)
      if columns_to_marshal
        marshaled_columns.concat( columns_to_marshal )
      else
        @@marshaled_columns[base_class] ||= [] 
      end
    end
  end

  module InstanceMethods
    def after_find
      true  # so Rails will invoke after_find callback
    end

    def marshal_data_columns
      @preserve_unmarshalled_data = {}
      self.class.marshaled_columns.each do |col|
        @preserve_unmarshalled_data[col] = self.send(col)
        self.send("#{col}=", Marshal.dump(@preserve_unmarshalled_data[col]) )
      end
      true
    end

    def restore_data_columns
      if @preserve_unmarshalled_data
        @preserve_unmarshalled_data.each do |col, value|
          self.send("#{col}=", value)
        end
      end
      @preserve_unmarshalled_data = nil
      true
    end

    def unmarshal_data_columns
      self.class.marshaled_columns.each do |col|
        stored_value = self.send(col)
        unless stored_value.blank?
          unmarshaled_value = stored_value =~ /^ *---/ ? YAML::load( stored_value ) : Marshal.load( stored_value )
          self.send("#{col}=", unmarshaled_value )
        end
        true
      end
    end

  private
    def set_data_unmarshaled(col, key_value_hash)
      send("#{col}=", (send(col) || {}).merge(key_value_hash))
      send("#{col}_will_change!")
      key_value_hash
    end
  
    def get_data_unmarshaled(col, key)
      return nil if send(col).blank?
      send(col)[key]
    end
  end
end

class ActiveRecord::Base
  def self.marshal(*columns_to_marshal)
    extend DataMarshaller::ClassMethods

    if marshaled_columns.empty?
      before_save :marshal_data_columns
      after_save  :restore_data_columns
      after_find  :unmarshal_data_columns
    end

    columns_to_marshal = columns_to_marshal.collect {|cn| cn.to_sym }
    marshaled_columns(columns_to_marshal)

    include DataMarshaller::InstanceMethods

    columns_to_marshal.each do |col|
      define_method("get_#{col}",  lambda {|key|            get_data_unmarshaled(col, key)                    })
      define_method("set_#{col}",  lambda {|key_value_hash| set_data_unmarshaled(col, key_value_hash)         })
      define_method("set_#{col}!", lambda {|key_value_hash| set_data_unmarshaled(col, key_value_hash) ; save! })
    end
  end
end
