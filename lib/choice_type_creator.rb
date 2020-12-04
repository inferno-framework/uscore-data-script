# frozen_string_literal: true

require 'pry'
require 'securerandom'

module DataScript
  # Class for making sure that every resource/profile that has a choice type (that's not
  # already covered by Synthea) has every choice type represented in the output.
  # For the moment, this only does Date/time related choice types, because they're easy to
  # automatically generate.
  class ChoiceTypeCreator
    SWAP_COUNT = 1
    MUST_SUPPORT_CHOICE_TYPES = {
      FHIR::DiagnosticReport =>
      {
        prefix: 'effective',
        suffixes: %w[DateTime Period],
        profiles: [
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-note',
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-lab'
        ]
      },
      FHIR::Immunization =>
      {
        prefix: 'occurrence',
        suffixes: %w[DateTime String],
        profiles: [
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-immunization'
        ]
      },
      FHIR::Observation =>
      {
        prefix: 'effective',
        suffixes: %w[DateTime Period],
        profiles: [
          'http://hl7.org/fhir/StructureDefinition/resprate',
          'http://hl7.org/fhir/StructureDefinition/heartrate',
          'http://hl7.org/fhir/StructureDefinition/bodyweight',
          'http://hl7.org/fhir/StructureDefinition/bp',
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-smokingstatus',
          'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-weight-for-height',
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab',
          'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-bmi-for-age',
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry',
          'http://hl7.org/fhir/us/core/StructureDefinition/head-occipital-frontal-circumference-percentile',
          'http://hl7.org/fhir/StructureDefinition/bodyheight',
          'http://hl7.org/fhir/StructureDefinition/bodytemp'
        ]
      },
      FHIR::Procedure =>
      {
        prefix: 'performed',
        suffixes: %w[DateTime Period],
        profiles: [
          'http://hl7.org/fhir/us/core/StructureDefinition/us-core-procedure'
        ]
      }
    }.freeze

    # Goes through the set of bundles, and ensure we have at least SWAP_COUNT resources
    # in each resource/profile pair listed above that conform to each choice type.
    # @param bundles [Array] an array of FHIR::Bundle objects
    # @return nil
    def self.check_choice_types(bundles)
      # Get the resources sorted by their resource type (fhir_models classname)
      resource_map = get_resources_by_class(bundles)
      resource_map.each do |resource_klass, resources|
        # Figure out if this resource is one that we need to add choice types for
        choice = MUST_SUPPORT_CHOICE_TYPES[resource_klass]
        next unless choice

        # Loop through each profile that this choice type applies to
        choice[:profiles].each do |profile_url|
          # get only the resources that claim conformance to that profile
          profile_resources = resources.select { |r| r&.meta&.profile&.include?(profile_url) }

          # Get an array with the attribute names, concatenated from the prefix/suffixes fields
          all_attrs = get_choice_attribute_names(choice)
          missing_attrs = get_choice_attribute_names(choice)

          # Loop through all the resources of this type, and delete the attr name if we find an attr with that choice type
          profile_resources.each do |resource|
            missing_attrs.each do |choice_attr|
              result = resource.send(choice_attr)
              missing_attrs.delete(choice_attr) if result
            end
            break if missing_attrs.empty?
          end

          # If we still have choice types left over, we need to add some of this type
          next if missing_attrs.empty?

          missing_attrs.each do |missing_attr|
            # If there are more than (SWAP_COUNT * the number of choices) resources of this class
            # Swap the choice type on SWAP_COUNT to the new type
            profile_resources.select { |resource| missing_attrs.none? { |attribute| resource.send(attribute) } }.first(SWAP_COUNT).each do |resource|
              # Get the first non-nil attribute value
              old_attr_type, old_attr_val = all_attrs.map do |a|
                av = resource.send(a)
                [a, av] if av
              end.compact.first
              # convert it (using some ugly if statements) to the new type
              new_val = convert_choice_types(old_attr_val, missing_attr, old_attr_type)
              if profile_resources.count > (SWAP_COUNT * all_attrs.count)
                puts "Swapping value for #{resource.class} with ID #{resource.id}"
                # set it on the resource
                resource.send("#{missing_attr}=", new_val)
                # and unset the old attribute
                resource.send("#{old_attr_type}=", nil)
              else
                puts "Creating new resource for #{resource.class} from #{resource.id}"
                # Create a new resource from the old one
                new_resource = FHIR::Json.from_json(resource.to_json)
                new_resource.id = SecureRandom.uuid
                # set it on the new resource
                new_resource.send("#{missing_attr}=", new_val)
                # and unset the old attribute
                new_resource.send("#{old_attr_type}=", nil)
                add_to_correct_bundle(new_resource, bundles)
              end
            end
          end
        end
      end
    end

    # Groups the bundled resources by their fhir_models class
    # @param bundles [Array] the resource bundles, in FHIR::Bundle format
    # @return [Hash] a hash where the keys are fhir_models class names (e.g. FHIR::Patient)
    # and the values are arrays of resources of that type
    def self.get_resources_by_class(bundles)
      resource_maps = bundles.collect do |bundle|
        bundle.entry.map(&:resource).group_by(&:class)
      end

      # Merge all the hashes from above into one big hash
      # (note: the * here is the 'splat' operator)
      {}.merge(*resource_maps) { |_, old, new| old.concat(new) }
    end

    # Creates the possible attribute names, given the prefix/suffixes lists in choice_hash
    # @param choice_hash [Hash] a hash, with a :prefix key (a string)
    # and a :suffix key (an array of strings)
    # @return [Array] each suffix appended to the prefix, in an array
    def self.get_choice_attribute_names(choice_hash)
      choice_hash[:suffixes].map { |e| "#{choice_hash[:prefix]}#{e}" }
    end

    # Converts value from the to_type to the from_type, based on some very simple logic.
    # @param value [Object] the value to be converted
    # @param to_type [String] the type of the value being passed in
    # @param from_type [String] the type of the desired return value
    # @return [Object] the converted type
    def self.convert_choice_types(value, to_type, from_type)
      if to_type.include?('Period')
        FHIR::Period.new(start: value, end: datetime_plus_1_hour(value))
      elsif to_type.include?('DateTime')
        if from_type.include?('Period')
          value.start ? value.start : value.end
        elsif from_type.include?('DateTime')
          value
        else
          raise "Not a known from type: #{from_type}"
        end
      elsif to_type.include?('String')
        parse_fhir_datetime(value).iso8601
      else
        raise "Not a known to type: #{to_type}"
      end
    end

    # Parses a FHIR DateTime string into a Ruby DateTime
    # @param datetime_string [String] the string representing the FHIR dateTime object
    # @return [DateTime] the Ruby DateTime created by parsing the FHIR DateTime string
    def self.parse_fhir_datetime(datetime_string)
      DateTime.strptime(datetime_string, '%Y-%m-%dT%H:%M:%S%z')
    end

    # Adds an hour (as 1/24th of a day) to a passed in datetime string,
    # and turns it back into a datetime string
    # @param datetime_string [String] the string representing a FHIR dateTime
    # @return [String] a string representing a FHIR DateTime 1 hour later
    def self.datetime_plus_1_hour(datetime_string)
      (parse_fhir_datetime(datetime_string) + 1.0 / 24.0).iso8601
    end

    # Finds the right bundle for a resource (based on the patient/subject ID),
    # Adds the patient to that bundle, and adds that entry to the Provenance
    # @param resource [FHIR::Resource] a fhir_models resource (or subclass)
    # @param bundles [Array] an array of FHIR::Bundle objects
    # @return nil
    def self.add_to_correct_bundle(resource, bundles)
      bundle = bundles.find { |b| DataScript::Constraints.patient(b).id == get_resource_patient_id(resource) }
      entry = create_bundle_entry(resource)
      bundle.entry << entry
      provenance = bundle.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
      provenance.target << FHIR::Reference.new
      provenance.target.last.reference = "urn:uuid:#{resource.id}"
    end

    # Creates a FHIR::Bundle::Entry object for a passed-in resource, with all the
    # expected values set
    # @param resource [FHIR::Resource] a fhir_models resource (or subclass)
    # @return [FHIR::Bundle::Entry] the Entry to be added to a bundle
    def self.create_bundle_entry(resource)
      entry = FHIR::Bundle::Entry.new
      entry.fullUrl = "urn:uuid:#{resource.id}"
      entry.resource = resource
      entry.request = FHIR::Bundle::Entry::Request.new
      entry.request.local_method = 'POST'
      entry.request.url = resource.resourceType
      entry
    end

    # Gets the "patient ID" out of a resource, normalizing for ones that call
    # the patient ID "subject" and those that call it "patient"
    # @param resource [FHIR::Resource] a fhir_models resource (or subclass)
    # @return [String] the patient ID, split out of the reference UUID
    def self.get_resource_patient_id(resource)
      patient_ref = resource.respond_to?(:subject) ? resource.subject : resource.patient
      patient_ref.reference.split(':').last
    end
  end
end
