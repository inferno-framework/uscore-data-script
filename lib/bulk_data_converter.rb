require 'json'

module DataScript
  class BulkDataConverter

    attr_accessor :keys
    attr_accessor :files
    attr_accessor :output

    def initialize(path = nil)
      @files = {}
      @output = "output/bulk"
      Dir.mkdir(@output) unless File.exists?(@output)
      if path
        @output = "output/bulk/#{path}"
        Dir.mkdir(@output) unless File.exists?(@output)
      end
    end

    def convert_to_bulk_data(bundle, patient_json_override = nil)
      if bundle.resourceType != 'Bundle'
        # This is not a Bundle, it is an individual resource
        json = JSON.parse( bundle.to_json )
        json = JSON.unparse(json)
        file = open_file(bundle)
        file.write(json)
        file.write("\n")
        return
      end

      @keys = {}

      # collect all the keys
      bundle.entry.each do |entry|
        keys[entry.fullUrl] = "#{entry.resource.resourceType}/#{entry.resource.id}"
      end

      # write each resource into the ndjson files
      bundle.entry.each_with_index do |entry, index|
        json = JSON.parse( entry.resource.to_json )
        json = JSON.unparse(json)
        json = patient_json_override if index == 0 && patient_json_override

        # rewrite all the references according to the keys
        keys.each do |key, value|
          json.gsub!(key, value)
        end
        # json.gsub!('"value": "DATAABSENTREASONEXTENSIONGOESHERE"', "\"_value\": { \"extension\": [ #{DataScript::Modifications.data_absent_reason.to_json} ] }")

        file = open_file(entry.resource)
        file.write(json)
        file.write("\n")
      end
    end

    def close
      files.each { |key, file| file.close }
    end

    def open_file(resource)
      file = files[resource.resourceType]
      unless file
        file = File.open("#{@output}/#{resource.resourceType}.ndjson", 'w:UTF-8')
        files[resource.resourceType] = file
      end
      file
    end

  end
end
