require 'yaml'

module Dopv
  module PersistentDisk
    class PersistentDiskError < StandardError; end

    class Entry
      DISK_DESC_KEYS = [:id, :name, :node, :pool, :size]

      attr_accessor :name, :id, :pool, :size, :node

      def initialize(attrs)
        if attrs.is_a?(Hash) && attrs.keys.sort == DISK_DESC_KEYS
          @node = attrs[:node]
          @name = attrs[:name]
          @id   = attrs[:id]
          @pool = attrs[:pool]
          @size = attrs[:size].to_i
        else
          raise PersistentDiskError, "Invalid disk entry"
        end
      end

      def ==(other)
        case other
        when Entry
          @node == other.node && @name == other.name && @id == other.id && @pool == other.pool
        when Hash
          @node == other[:node] && @name == other[:name] && @id == other[:id] && @pool == other[:pool]
        else
          false
        end
      end

      def update(attrs={})
        raise PersistentDiskError, "Update attributes must be a hash" unless attrs.is_a?(Hash)
        @node = attrs[:node] if attrs[:node]
        @name = attrs[:name] if attrs[:name]
        @id   = attrs[:id]   if attrs[:id]
        @pool = attrs[:pool] if attrs[:pool]
        @size = attrs[:size].to_i if attrs[:size]
        self
      end

      def to_s
        "Disk: #{@name}\n  Node: #{@node}\n  Id: #{@id}\n  Pool: #{@pool}\n  Size: #{@size}"
      end

      def to_hash
        { :name => @name, :id => @id, :pool => @pool, :size => @size }
      end
    end

    class DB

      def initialize(state_store, node_name)
        @state_store = state_store
        @node_name = node_name
        @state_store.transaction do
          @state_store[:data_volumes] ||= {}
          @state_store[:data_volumes][@node_name] ||= []
        end
      end

      def volumes
        @state_store.transaction(true) { entries }
      end

      def append(entry)
        @state_store.transaction do
          entries.each do |disk|
            if disk == entry
              raise PersistentDiskError, "Disk #{disk.name} already exists for node #{disk.node}"
            end
          end
          if entry.is_a?(Entry)
            @entries << entry
            @state_store[:data_volumes][@node_name] << entry.to_hash
          else
            @entries << Entry.new(entry)
            @state_store[:data_volumes][@node_name] << entry
          end
        end
      end

      def <<(entry)
        append(entry)
      end

      def add(entry)
        append(entry)
      end

      def update(entry, attrs={})
        @state_store.transaction do
          index = entries.index {|stored_entry| stored_entry = entry}
          if index.nil?
            raise PersistentDiskError, "Entry update: Disk entry not found #{entry.to_s}"
          end
          @entries[index].update(attrs)
          @state_store[:data_volumes][@node_name][index] = @entries[index]
          @entries[index]
        end
      end

      def delete(entry)
        @state_store.transaction do
          index = entries.index {|stored_entry| stored_entry = entry}
          if index.nil?
            raise PersistentDiskError, "Entry update: Disk entry not found #{entry.to_s}"
          end

          @entries.detele_at(index)
          @state_store[:data_volumes][@node_name].detele_at(index)
          entry
        end
      end

      private

      def entries
        @entries ||= @state_store[:data_volumes][@node_name].map do |raw_entry|
          symbolized_entry = Hash[raw_entry.map {|k1, v1| [k1.to_sym, v1] }]
          merged_entry = symbolized_entry.merge({:node => @node_name})
          Dopv::PersistentDisk::Entry.new(merged_entry)
        end
      end

    end
  end
end
