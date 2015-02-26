require 'yaml'

module Dopv
  module PersistentDisk
    def self.load(db_file)
      DB.new(db_file)
    end
    
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
          raise Errors::PersistentDiskError, "Invalid disk entry."
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
        raise Errors::PersistentDiskError, "Update attributes must be a hash." unless attrs.is_a?(Hash)
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
        { "name" => @name, "id" => @id, "pool" => @pool, "size" => @size, "node" => @node }
      end
    end

    class DB
      @@db = nil
      @@dirty = false

      @db_file = nil

      def initialize(db_file)
        @db_file = db_file
        @@db = load_file if @@db.nil?
      end
      
      def each(&block)
        @@db.each(&block)
      end

      def find
        each {|disk| return disk if yield(disk)}
        nil
      end

      def find_all
        disks = []
        each {|disk| disks << disk if yield(disk)}
        disks
      end
      
      def append(entry)
        each do |disk|
          if disk == entry
            raise Errors::PersistentDiskError, "Disk #{disk.name} already exists for node #{disk.node}."
          end
        end
        if entry.is_a?(Entry)
          @@db << entry
        else
          @@db << Entry.new(entry)
        end
        @@dirty = true
      end
      
      def <<(entry)
        append(entry)
      end

      def add(entry)
        append(entry)
      end

      def update(entry, attrs={})
        case entry
        when Entry
          disk = find {|d| d == entry}
        when Hash
          raise Errors::PersistentDiskError, "Entry hash must contain a node name." unless entry.has_key?(:node)
          raise Errors::PersistentDiskError, "Entry hash must contain a disk name." unless entry.has_key?(:name)
          disk = find {|d| d.node == entry[:node] && d.name == entry[:name]}
        else
          raise Errors::PersistentDiskError, "Disk entry must be Hash or Entry."
        end
        disk.update(attrs) if disk
      end

      def delete(entry)
        case entry
        when Entry
          @@db.delete_if {|disk| disk == entry}
        when Hash
          raise Errors::PersistentDiskError, "Entry hash must contain at least a node name." unless entry.has_key?(:node)
          if entry.has_key?(:name)
            @@db.delete_if {|disk| disk.node == entry[:node] && disk.name == entry[:name]}
          else
            @@db.delete_if {|disk| disk.node == entry[:node]}
          end
        end
      end

      def load_file
        db = []
        begin
          YAML.load_file(@db_file).each do |k, v|
            v.each {|entry| db << Entry.new(Hash[entry.map {|k1, v1| [k1.to_sym, v1]}].merge(:node => k))}
          end
        rescue
          []
        end
        db
      end
      
      def to_yaml
        db = {}
        each {|disk| (db[disk.node] ||= []) << disk.to_hash.delete_if {|k| k == disk.node}}
        db.to_yaml
      end
      
      def save(force=false)
        if @@dirty || force
          File.open(@db_file, 'w') {|f| f.write to_yaml}
        end
      end
      
      def to_s
        each {|disk| disk.to_s}
      end
    end
  end
end
