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
          @size = attrs[:size]
        else
          raise Errors::PersistentDiskError, "Invalid disk entry"
        end
      end

      def ==(other)
        case other
        when Entry
          @node == other.node && name == other.name && id == other.id
        when Hash
          @node == other[:node] && @name == other[:name] && @id == other[:id]
        else
          false
        end
      end

      def update(attrs={})
        raise Errors::PersistentDiskError, "Update attributes must be of hash type" unless attrs.is_a?(Hash)
        @node = attrs[:node] if attrs[:node]
        @name = attrs[:name] if attrs[:name]
        @id   = attrs[:id]   if attrs[:id]
        @pool = attrs[:pool] if attrs[:pool]
        @size = attrs[:size] if attrs[:size]
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
            raise Errors::PersistentDiskError, "Disk #{disk.name} already exists for node #{disk.node}"
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
        raise Errors::PersistentDiskError, "Entry must be of hash type" unless entry.is_a?(Hash)
        disk = find {|d| d.node == entry[:node] && d.name == entry[:name]}
        disk.update(attrs) if disk
      end

      def delete(entry)
        raise Errors::PersistentDiskError, "Entry must be of hash type" unless entry.is_a?(Hash)
        if entry.has_key?(:node)
          if entry.has_key?(:name)
            @@db.delete_if {|disk| disk.node == entry[:node] && disk.name == entry[:name]}
          else
            @@db.delete_if {|disk| disk.node == entry[:node]}
          end
        end
      end

      def load_file
        db = []
        return db unless File.exist?(@db_file)
        YAML.load_file(@db_file).each do |k, v|
          v.each {|entry| db << Entry.new(Hash[entry.map {|k1, v1| [k1.to_sym, v1]}].merge(:node => k))}
        end
        db
      end
      
      def to_yaml
        db = {}
        each {|disk| (db[disk.node] ||= []) << disk.to_hash.delete_if{|k| k == disk.node}}
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
