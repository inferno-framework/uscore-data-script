require 'securerandom'
require_relative 'constraints'

module DataScript
  class Modifications
    def self.modify!(results)
      # results is an Array of FHIR::Bundle objects,
      # where the first resource is a Patient.

      # Remove unwanted patient extensions and identifers
      results.each do |bundle|
        # first, remove unwanted patient extensions
        bundle.entry.first.resource.extension.delete_if do |extension|
          extension.url.start_with? 'http://synthetichealth.github.io'
        end

        # next, remove unwanted patient identifier
        bundle.entry.first.resource.identifier.delete_if do |identifier|
          identifier.system.start_with? 'http://standardhealthrecord.org'
        end
      end

      # create vitalspanel
      panel_members = [
        'http://hl7.org/fhir/StructureDefinition/resprate',
        'http://hl7.org/fhir/StructureDefinition/heartrate',
        'http://hl7.org/fhir/StructureDefinition/oxygensat',
        'http://hl7.org/fhir/StructureDefinition/bodytemp',
        'http://hl7.org/fhir/StructureDefinition/bodyheight',
        'http://hl7.org/fhir/StructureDefinition/headcircum',
        'http://hl7.org/fhir/StructureDefinition/bodyweight',
        'http://hl7.org/fhir/StructureDefinition/bmi',
        'http://hl7.org/fhir/StructureDefinition/bp'
      ]
      new_vitalspanels = 0
      results.each do |bundle|
        # find the provenance for this bundle
        provenance = bundle.entry.find { |e| e.resource.resourceType == 'Provenance' }
        # get all the encounters
        encounters = bundle.entry.select {|e| e.resource.resourceType == 'Encounter'}
        # get all the observations
        observations = bundle.entry.select {|e| e.resource.resourceType == 'Observation'}
        # add a vitalspanel to each encounter where appropriate
        encounters.each do |entry|
          encounter_url = entry.fullUrl
          obs = observations.select {|e| e.resource.encounter.reference == encounter_url}
          vitals = obs.select {|e| e.resource.meta && (e.resource.meta.profile & panel_members).any?}
          if vitals && !vitals.empty?
            # create a vitalspanel
            vitalspanel = FHIR::Observation.new
            vitalspanel.id = SecureRandom.uuid
            vitalspanel.status = 'final'
            vitalspanel.meta = FHIR::Meta.new
            vitalspanel.meta.profile = [ 'http://hl7.org/fhir/StructureDefinition/vitalspanel', 'http://hl7.org/fhir/StructureDefinition/vitalsigns' ]
            vitalspanel.category = vitals.first.resource.category
            vitalspanel.code = FHIR::CodeableConcept.new
            vitalspanel.code.coding = [ FHIR::Coding.new ]
            vitalspanel.code.coding.first.code = '85353-1'
            vitalspanel.code.coding.first.system = 'http://loinc.org'
            vitalspanel.code.coding.first.display = 'Vital signs, weight, height, head circumference, oxygen saturation and BMI panel'
            vitalspanel.code.text = 'Vital signs, weight, height, head circumference, oxygen saturation and BMI panel'
            vitalspanel.effectiveDateTime = vitals.first.resource.effectiveDateTime
            vitalspanel.encounter = vitals.first.resource.encounter
            vitalspanel.issued = vitals.first.resource.issued
            vitalspanel.subject = vitals.first.resource.subject
            vitalspanel.hasMember = []
            vitals.each do |member|
              reference = FHIR::Reference.new
              reference.reference = member.fullUrl
              reference.display = member.resource.code.text
              vitalspanel.hasMember << reference
            end
            # create an entry
            bundle.entry << create_bundle_entry(vitalspanel)
            # add the new vitalspanel to the provenance resource
            if provenance
              provenance.resource.target << FHIR::Reference.new
              provenance.resource.target.last.reference = "urn:uuid:#{vitalspanel.id}"
            end
            new_vitalspanels += 1
          end
        end
      end
      puts "  - Created #{new_vitalspanels} vitalspanels"

      # select by smoking status
      selection_smoker = results.find {|b| DataScript::Constraints.smoker(b)}
      unless selection_smoker
        # if there is no smoker, choose the oldest patient
        # and make them start smoking at the end of their life...
        # because why not?
        oldest = results.sort {|a,b| a.entry.first.resource.birthDate <=> b.entry.first.resource.birthDate }.first
        alter_smoking_status(oldest)
        puts "  - Altered Smoker:     #{oldest.entry.first.resource.id}"
      end

      # sort the results by number of Conditions
      results.sort do |a,b|
        count_a = a.entry.count {|e| e.resource.resourceType == 'Condition'}
        count_b = b.entry.count {|e| e.resource.resourceType == 'Condition'}
        count_a <=> count_b
      end
      # select the person with the most Conditions
      selection_conditions = results.last
      alter_condition(selection_conditions)
      puts "  - Altered Condition:  #{selection_conditions.entry.first.resource.id}"

      # select someone with the most numerous gender
      # from the people remaining, and remove their name
      selection_name = pick_by_gender(results)
      remove_name(selection_name)
      puts "  - Altered Name:       #{selection_name.entry.first.resource.id}"

      # select by medication
      selection_medication = results.find {|b| DataScript::Constraints.has(b, FHIR::Medication)}
      unless selection_medication
        # if there is no free-standing Medication resource, we need to make one.
        bundle = results.find { |b| DataScript::Constraints.has(b, FHIR::MedicationRequest) }
        medreq = bundle.entry.find { |e| e.resource.resourceType == 'MedicationRequest' }
        provenance = bundle.entry.find { |e| e.resource.resourceType == 'Provenance' }
        # create the medication
        med = FHIR::Medication.new
        med.id = SecureRandom.uuid
        med.status = 'active'
        med.meta = FHIR::Meta.new
        med.meta.profile = [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-medication' ]
        med.code = medreq.resource.medicationCodeableConcept
        # alter the MedicationRequest to refer to the Medication resource and not a code
        medreq.resource.medicationCodeableConcept = nil
        medreq.resource.medicationReference = FHIR::Reference.new
        medreq.resource.medicationReference.reference = "urn:uuid:#{med.id}"
        # add the Medication as a new Bundle entry
        bundle.entry << create_bundle_entry(med)
        # add the Medication into the provenance
        provenance.resource.target << FHIR::Reference.new
        provenance.resource.target.last.reference = "urn:uuid:#{med.id}"
        puts "  - Altered Medication: #{bundle.entry.first.resource.id}"
      end

      # remove all resources from bundles that are not US Core profiles
      results.each do |bundle|
        bundle.entry.delete_if {|e| ['Claim','ExplanationOfBenefit','ImagingStudy'].include?(e.resource.resourceType)}
      end
      puts "  - Removed resources out of scope for US Core."
      # There are probably some observations remaining after this that are not US Core profiles,
      # but they likely are referenced from DiagnosticReports which are US Core profiled.

      # delete provenance references to removed resources
      results.each do |bundle|
        provenance = bundle.entry.find {|e| e.resource.resourceType == 'Provenance' }.resource
        uuids = bundle.entry.map {|e| e.fullUrl}
        provenance.target.keep_if {|reference| uuids.include?(reference.reference) }
      end
      puts "  - Rewrote Provenance targets."

      # Add Group
      results << create_group(results)

      # The JSON from this exported patient will need to be manually altered to
      # create primitive extensions, so we specifically return just this patient bundle.
      selection_name
    end

    def self.pick_by_gender(results)
      # pick someone of the more represented gender
      # in other words, if there are more males, pick a male.
      # otherwise if there are more females, pick a female.
      females = results.count {|b| b.entry.first.resource.gender == 'female'}
      males = results.length - females
      if males > females
        selection = results.find {|b| b.entry.first.resource.gender == 'male'}
      else
        selection = results.find {|b| b.entry.first.resource.gender == 'female'}
      end
      selection
    end

    def self.remove_name(bundle)
      # Replace name with empty name.
      # Technically this doesn't validate because of us-core-8:
      # Patient.name.given or Patient.name.family or both SHALL be present [family.exists() or given.exists()]
      #
      # The JSON from this exported patient will need to be manually altered to
      # create primitive extensions.
      human_name = FHIR::HumanName.new
      # If the us-core-8 invariant changes to allow data absent reason on name, then we can enable the next line
      # human_name.extension = [ data_absent_reason ]
      bundle.entry.first.resource.name = [ human_name ]
    end

    def self.alter_condition(bundle)
      # randomly pick one of their Conditions
      random_condition = bundle.entry.map {|e| e.resource }.select {|r| r.resourceType == 'Condition'}.shuffle.last
      # and replace the category with a data-absent-reason
      unknown = FHIR::CodeableConcept.new
      unknown.extension = [ data_absent_reason ]
      random_condition.category = [ unknown ]
    end

    def self.data_absent_reason
      extension = FHIR::Extension.new
      extension.url = 'http://hl7.org/fhir/StructureDefinition/data-absent-reason'
      extension.valueCode = 'unknown'
      extension
    end

    def self.alter_smoking_status(bundle)
      last_smoking_observation = bundle.entry.select {|e| e.resource.resourceType == 'Observation' && e.resource.code.text == 'Tobacco smoking status NHIS' }.last.resource
      coding = FHIR::Coding.new
      coding.system = 'http://snomed.info/sct'
      coding.code = '449868002'
      coding.display = 'Current every day smoker'
      smoker = FHIR::CodeableConcept.new
      smoker.coding = [ coding ]
      smoker.text = 'Current every day smoker'
      last_smoking_observation.valueCodeableConcept = smoker
    end

    def self.create_group(results)
      group = FHIR::Group.new
      group.id = SecureRandom.uuid
      group.identifier = [ FHIR::Identifier.new ]
      group.identifier.first.system = 'urn:ietf:rfc:3986'
      group.identifier.first.value = "urn:uuid:#{group.id}"
      group.active = true
      group.type = 'person'
      group.actual = true
      group.name = 'Synthea US Core Patients'
      group.quantity = results.length
      group.member = []
      results.each do |bundle|
        group_member = FHIR::Group::Member.new
        group_member.entity = FHIR::Reference.new
        group_member.entity.reference = bundle.entry.first.fullUrl
        group.member << group_member
      end
      group
    end

    def self.create_bundle_entry(resource)
        entry = FHIR::Bundle::Entry.new
        entry.fullUrl = "urn:uuid:#{resource.id}"
        entry.resource = resource
        entry.request = FHIR::Bundle::Entry::Request.new
        entry.request.local_method = 'POST'
        entry.request.url = resource.resourceType
        entry
    end
  end
end