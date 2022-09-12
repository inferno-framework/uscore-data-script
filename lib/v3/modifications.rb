# frozen_string_literal: true

require 'base64'
require 'securerandom'
require_relative 'constraints'
require_relative '../choice_type_creator'
require 'fhir_models'
require 'time'

module DataScript
  class Modifications
    DESIRED_MAX = 20

    def self.modify!(results, random_seed = 3)
      FHIR.logger.level = :info

      # Create a random number generator, to pass to things that need randomness
      rng = Random.new(random_seed)
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

        # make sure every patient has a postalCode
        # some towns do not have postalCodes
        bundle.entry.first.resource.address.first.postalCode = '01999' unless bundle.entry.first.resource.address.first.postalCode

        # finally, make sure every patient has an address period
        bundle.entry.first.resource.address.first.period = FHIR::Period.new
        bundle.entry.first.resource.address.first.period.start = bundle.entry.first.resource.birthDate
      end

      # Make sure there aren't stupid numbers of every resource type
      missing_profiles = DataScript::Constraints::REQUIRED_PROFILES.dup
      results.each do |bundle|
        resource_counts = get_resource_counts(bundle)
        provenance = bundle.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
        resource_counts.each do |type, count|
          next unless count >= DESIRED_MAX

          deleted_ids = []
          dr_observations = get_diagreport_referenced_observations(bundle)
          dr_notes = get_docref_referenced_attachments(bundle)
          encounter_refs = get_referenced_encounters(bundle)
          reason_refs = get_referenced_reasons(bundle)
          addresses_refs = get_addresses(bundle)
          medication_refs = get_medreqs_with_med_references(bundle)
          references = (dr_observations + dr_notes + encounter_refs + reason_refs + addresses_refs + medication_refs).compact.uniq
          bundle.entry.find_all { |e| e.resource.resourceType == type }.shuffle(random: rng).each do |e|
            break if deleted_ids.count >= (count - DESIRED_MAX)

            profiles = e.resource&.meta&.profile || []

            # Only delete it if it's not somehow important
            if !references.include?(e.resource.id) &&
               !(e.resource.is_a?(FHIR::Observation) && e.resource&.code&.text.start_with?('Tobacco smoking status')) &&
               (missing_profiles & profiles).empty?
              deleted_ids << e.resource.id
            elsif !(missing_profiles & profiles).empty?
              missing_profiles -= profiles
            end
          end
          bundle.entry.delete_if { |e| deleted_ids.include? e.resource.id }
          remove_provenance_targets(deleted_ids, provenance)
        end
      end

      # add reaction.manifestation to allergy intolerance result because of must support changes in 3.1.1
      already_contains_reaction_manifestation =
        results.any? do |bundle|
          bundle
            .entry
            .select { |e| e.resource.is_a? FHIR::AllergyIntolerance }
            .map(&:resource)
            .any? do |resource|
              resource.reaction.any? { |reaction| reaction.manifestation.any? }
            end
        end
      unless already_contains_reaction_manifestation
        results.each do |bundle|
          allergy_intoleranace_resource = bundle.entry.find { |e| e.resource.is_a? FHIR::AllergyIntolerance }&.resource
          next if allergy_intoleranace_resource.nil?

          reaction = FHIR::AllergyIntolerance::Reaction.new
          manifestation = create_codeable_concept('http://snomed.info/sct', '271807003', 'skin rash')
          reaction.manifestation << manifestation
          allergy_intoleranace_resource.reaction << reaction
          puts "  - Altered AllergyIntolerance: #{allergy_intoleranace_resource.id}"
          break
        end
      end

      # Add discharge disposition to every encounter referenced by a medicationRequest of each record
      # This is necessary (rather than just one) because of how Inferno Program has to get Encounters
      results.each do |bundle|
        encounter_urls = bundle.entry.find_all { |e| e.resource.resourceType == 'MedicationRequest' }.map { |e| e.resource&.encounter&.reference }.compact.uniq
        encounter_urls.each do |encounter_url|
          encounter_entry = bundle.entry.find { |e| e.fullUrl == encounter_url }
          encounter = encounter_entry.resource
          encounter.hospitalization = FHIR::Encounter::Hospitalization.new
          encounter.hospitalization.dischargeDisposition = create_codeable_concept('http://www.nubc.org/patient-discharge','01','Discharged to home care or self care (routine discharge)')
        end
      end

      # Make sure at least one organization has an NPI
      organization_entry = results.last.entry.find { |e| e.resource.resourceType == 'Organization' }
      organization = organization_entry.resource
      # Add a 10 digit NPI
      organization.identifier << FHIR::Identifier.new
      organization.identifier.last.system = 'http://hl7.org/fhir/sid/us-npi'
      organization.identifier.last.value = '9999999999'
      # Add a CLIA
      organization.identifier << FHIR::Identifier.new
      organization.identifier.last.system = 'urn:oid:2.16.840.1.113883.4.7'
      organization.identifier.last.value = '9999999999'

      # Add a PractitionerRole.endpoint
      pr_entry = results.last.entry.find { |e| e.resource.resourceType == 'PractitionerRole' }
      pr = pr_entry.resource
      pr.endpoint = [ FHIR::Reference.new ]
      pr.endpoint.first.reference = '#endpoint'
      pr.endpoint.first.type = 'Endpoint'
      endpoint = FHIR::Endpoint.new
      endpoint.id = 'endpoint'
      endpoint.status = 'active'
      endpoint.connectionType = create_codeable_concept('http://terminology.hl7.org/CodeSystem/endpoint-connection-type', 'direct-project', 'Direct Project').coding.first
      endpoint.payloadType = [ create_codeable_concept('http://terminology.hl7.org/CodeSystem/endpoint-payload-type', 'any', 'Any') ]
      endpoint.address = "mailto:#{pr.telecom.last.value}"
      pr.contained = [endpoint]

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
      results.sort! do |a,b|
        count_a = a.entry.count {|e| e.resource.resourceType == 'Condition'}
        count_b = b.entry.count {|e| e.resource.resourceType == 'Condition'}
        count_a <=> count_b
      end
      # select the person with the most Conditions
      selection_conditions = results.last
      altered = alter_condition(selection_conditions, rng)
      puts "  - Altered Condition:  #{altered.id}"

      # select someone with the most numerous gender
      # from the people remaining, and remove their name
      unless MRBURNS
        selection_name = pick_by_gender(results)
        remove_name(selection_name)
        puts "  - Altered Name:       #{selection_name.entry.first.resource.id}"
      end

      # select by clinical note
      selection_note = results.find {|b| DataScript::Constraints.has(b, FHIR::DocumentReference)}
      if selection_note
        # modify it to have a URL rather than base64 encoded data
        docref = selection_note.entry.reverse.find { |e| e.resource.resourceType == 'DocumentReference' }.resource
        report = selection_note.entry.reverse.find { |e|
          e&.resource&.resourceType == 'DiagnosticReport' &&
            e&.resource&.presentedForm&.first&.data == docref&.content&.first&.attachment&.data }&.resource
        url = 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'
        docref.content.first.attachment.contentType = 'application/pdf'
        docref.content.first.attachment.data = nil
        docref.content.first.attachment.url = url
        report.presentedForm.first.contentType = 'application/pdf'
        report.presentedForm.first.data = nil
        report.presentedForm.first.url = url
        puts "  - Altered DocumentReference URL: #{docref.id}"
        puts "  - Altered DiagnosticReport  URL: #{report.id}"
      else
        puts "  * FAILED to find DocumentReference!"
      end

      # collect all the clinical notes and modify codes so we have at least one of each type
      category_types = [
        [ 'Cardiology', 'LP29708-2' ],
        [ 'Pathology', 'LP7839-6' ],
        [ 'Radiology', 'LP29684-5' ]
      ]
      note_types = [
        [ 'Consultation note', '11488-4' ],
        [ 'Discharge summary', '18842-5' ],
        [ 'History and physical note', '34117-2' ],
        [ 'Procedure note', '28570-0' ],
        [ 'Progress note', '11506-3' ],
        [ 'Referral note', '57133-1' ],
        [ 'Surgical operation note', '11504-8' ],
        [ 'Nurse Note', '34746-8' ]
      ]
      category_types.map! {|type| create_codeable_concept('http://loinc.org',type.last,type.first) }
      note_types.map! {|type| create_codeable_concept('http://loinc.org',type.last,type.first) }
      # grab all the clinical notes
      all_docref = results.map {|b| b.entry.select {|e| e.resource.resourceType == 'DocumentReference'}.map {|e| e.resource} }.flatten
      all_report = results.map {|b| b.entry.select {|e| e.resource.resourceType == 'DiagnosticReport'}.map {|e| e.resource} }.flatten
      # there are more DiagnosticReports than DocumentReferences,
      # so we need to filter them...
      docref_data = all_docref.map {|r| r.content.first.attachment.data}
      matching_report = all_report.select { |r| r.presentedForm.length >= 1 && docref_data.include?(r.presentedForm.first.data) }

      # need to replace the codes...
      # we will use a uniform distribution of note_types
      note_types_index = 0
      category_types_index = 0
      all_docref.zip(matching_report).each do |docref, report|
        break if report.nil?
        docref.type = note_types[note_types_index]
        report.category = [ category_types[category_types_index] ]
        report.code = note_types[note_types_index]
        note_types_index += 1
        category_types_index += 1
        note_types_index = 0 if note_types_index >= note_types.length
        category_types_index = 0 if category_types_index >= category_types.length
      end
      puts "  - Altered codes for #{all_docref.length} clinical notes."

      all_docref.each do |docref|
        docref&.identifier&.each {|id| id.value = "urn:uuid:#{id.value}" if (id.system == 'urn:ietf:rfc:3986' && !id.value&.start_with?('urn'))}
      end
      puts "  - Altered identifiers for #{all_docref.length} clinical notes."

      # select by medication
      selection_medication = results.find {|b| DataScript::Constraints.has(b, FHIR::Medication)}
      unless selection_medication
        # if there is no free-standing Medication resource, we need to make one.
        med_bundle = results.find { |b| DataScript::Constraints.has(b, FHIR::MedicationRequest) }
        medreq = med_bundle.entry.find { |e| e.resource.resourceType == 'MedicationRequest' }
        provenance = med_bundle.entry.find { |e| e.resource.resourceType == 'Provenance' }
        # create the medication
        med = FHIR::Medication.new
        med.id = SecureRandom.uuid
        med.status = 'active'
        med.meta = FHIR::Meta.new
        med.meta.profile = [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-medication' ]
        med.code = medreq.resource.medicationCodeableConcept
        # alter the MedicationRequest to refer to the Medication resource and not a code
        medreq.resource.reportedBoolean = true
        medreq.resource.medicationCodeableConcept = nil
        medreq.resource.medicationReference = FHIR::Reference.new
        medreq.resource.medicationReference.reference = "urn:uuid:#{med.id}"
        medreq.resource.status = 'active'
        # add the Medication as a new Bundle entry
        med_bundle.entry << create_bundle_entry(med)
        # add the Medication into the provenance
        provenance.resource.target << FHIR::Reference.new
        provenance.resource.target.last.reference = "urn:uuid:#{med.id}"
        puts "  - Altered Medication: #{med_bundle.entry.first.resource.id}"
      end

      # change one medication request from an order to a self prescription, if needed
      # we need at least two intents in order to demonstrate the multi-or search requirement for intent
      any_non_order = results.any? {|b| b.entry.any?{|e| e.resource.resourceType == 'MedicationRequest' && e.resource.intent != 'order' }}
      selection_medication_request = results.find {|b| DataScript::Constraints.has(b, FHIR::MedicationRequest)}
      if !any_non_order && selection_medication_request
        changed_medication = selection_medication_request.entry.select { |e| e.resource.resourceType == 'MedicationRequest'}.last.resource
        changed_medication.intent = 'plan'
        changed_medication.reportedBoolean = true
        changed_medication.reportedReference = nil
        changed_medication.requester = changed_medication.subject.clone
        changed_medication.encounter = nil
        puts "  - Altered Medication Request to have 'plan' intent: #{changed_medication.id}"
      end

      # select by device
      selection_device = results.find {|b| DataScript::Constraints.has(b, FHIR::Device)}
      if selection_device
        # if there is a Device resource, we need to clone it and use carrierAIDC.
        device = selection_device.entry.find { |e| e.resource.resourceType == 'Device' }
        provenance = selection_device.entry.find { |e| e.resource.resourceType == 'Provenance' }
        # create the new Device
        dev = FHIR::Device.new(device.resource.to_hash)
        dev.id = SecureRandom.uuid
        dev.udiCarrier.first.carrierHRF = nil
        barcode_file_path = File.join(File.dirname(__FILE__), '../barcode.png')
        barcode_file = File.open(barcode_file_path, 'rb')
        barcode_data = barcode_file.read
        barcode_file.close
        dev.udiCarrier.first.carrierAIDC = Base64.encode64(barcode_data)
        # add the Device as a new Bundle entry
        selection_device.entry << create_bundle_entry(dev)
        # add the Device into the provenance
        provenance.resource.target << FHIR::Reference.new
        provenance.resource.target.last.reference = "urn:uuid:#{dev.id}"
        puts "  - Cloned Device: #{selection_device.entry.first.resource.id}"
      end

      # select an Immunization
      selection_immunization = results.find {|b| DataScript::Constraints.has(b, FHIR::Immunization)}
      if selection_immunization
        # if there is an Immunization resource, we need to clone it and use carrierAIDC.
        immunization_entry = selection_immunization.entry.find { |e| e.resource.resourceType == 'Immunization' }
        immunization = immunization_entry.resource
        immunization.vaccineCode = create_codeable_concept('http://terminology.hl7.org/CodeSystem/data-absent-reason', 'unknown', 'Unknown')
        immunization.statusReason = create_codeable_concept('http://terminology.hl7.org/CodeSystem/v3-ActReason', 'OSTOCK', 'product out of stock')
        immunization.status = 'not-done'
        puts "  - Altered Immunization: #{selection_immunization.entry.first.resource.id}"
      end

      # select Bundle with Pulse Oximetry
      selection_pulse_ox = results.find {|b| DataScript::Constraints.has_pulse_ox(b)}
      if selection_pulse_ox
        provenance = selection_pulse_ox.entry.find { |e| e.resource.resourceType == 'Provenance' }
        pulse_ox_entry = selection_pulse_ox.entry.find {|e| e.resource&.meta&.profile&.include? 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry' }
        pulse_ox_clone = nil
        2.times do
          pulse_ox_clone = FHIR.from_contents(pulse_ox_entry.resource.to_json)
          pulse_ox_clone.id = SecureRandom.uuid
          # Add the must support components
          pulse_ox_clone.component = []
          # First component is flow rate
          pulse_ox_clone.component << FHIR::Observation::Component.new
          pulse_ox_clone.component.last.code = create_codeable_concept('http://loinc.org','3151-8', 'Inhaled oxygen flow rate')
          pulse_ox_clone.component.last.valueQuantity = FHIR::Quantity.new
          pulse_ox_clone.component.last.valueQuantity.value = 6
          pulse_ox_clone.component.last.valueQuantity.unit = 'L/min'
          pulse_ox_clone.component.last.valueQuantity.system = 'http://unitsofmeasure.org'
          pulse_ox_clone.component.last.valueQuantity.code = 'L/min'
          # Second component is concentration
          pulse_ox_clone.component << FHIR::Observation::Component.new
          pulse_ox_clone.component.last.code = create_codeable_concept('http://loinc.org','3150-0', 'Inhaled oxygen concentration')
          pulse_ox_clone.component.last.valueQuantity = FHIR::Quantity.new
          pulse_ox_clone.component.last.valueQuantity.value = 40
          pulse_ox_clone.component.last.valueQuantity.unit = '%'
          pulse_ox_clone.component.last.valueQuantity.system = 'http://unitsofmeasure.org'
          pulse_ox_clone.component.last.valueQuantity.code = '%'
          # add the Pulse Oximetry as a new Bundle entry
          selection_pulse_ox.entry << create_bundle_entry(pulse_ox_clone)
          # add the Pulse Oximetry into the provenance
          provenance.resource.target << FHIR::Reference.new
          provenance.resource.target.last.reference = "urn:uuid:#{pulse_ox_clone.id}"
        end
        # for the second clone, data absent reason the components
        pulse_ox_clone.component.each do |component|
          component.valueQuantity = nil
          component.dataAbsentReason = create_codeable_concept('http://terminology.hl7.org/CodeSystem/data-absent-reason', 'unknown', 'Unknown')
        end
        puts "  - Cloned Pulse Oximetry and Added Components: #{selection_pulse_ox.entry.first.resource.id}"
      end

      goal_bundle = results.find { |b| DataScript::Constraints.has(b, FHIR::Goal) }
      unless goal_bundle
        goal_bundle = results.find { |b| DataScript::Constraints.has(b, FHIR::Patient) }
        goal = FHIR::Goal.new
        goal.meta = FHIR::Meta.new
        goal.meta.profile = ['http://hl7.org/fhir/us/core/StructureDefinition/us-core-goal']
        goal.id = SecureRandom.uuid
        goal.lifecycleStatus = 'active'
        goal.description = create_codeable_concept('http://snomed.info/sct', '281004', 'Alcoholic dementia')
        goal.subject = { reference: "urn:uuid:#{DataScript::Constraints.patient(goal_bundle).id}" }
        goal_target = FHIR::Goal::Target.new
        goal_target.dueDate = Time.now.strftime("%Y-%m-%d")
        goal.target << goal_target
        goal_bundle.entry << create_bundle_entry(goal)
        goal_provenance = goal_bundle.entry.find { |e| e.resource.resourceType == 'Provenance' }
        goal_provenance.resource.target << FHIR::Reference.new
        goal_provenance.resource.target.last.reference = "urn:uuid:#{goal.id}"
      end

      observation_profiles_valueCodeableConcept_required = [
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-smokingstatus'
      ]
      observation_profiles_components_required = [
        'http://hl7.org/fhir/StructureDefinition/bp'
      ]
      observation_profiles = [
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-smokingstatus',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry',
        'http://hl7.org/fhir/us/core/StructureDefinition/head-occipital-frontal-circumference-percentile',
        'http://hl7.org/fhir/StructureDefinition/resprate',
        'http://hl7.org/fhir/StructureDefinition/heartrate',
        'http://hl7.org/fhir/StructureDefinition/bodytemp',
        'http://hl7.org/fhir/StructureDefinition/bodyheight',
        'http://hl7.org/fhir/StructureDefinition/bodyweight',
        'http://hl7.org/fhir/StructureDefinition/bp'
      ]

      # Add missing Head Circumference Percent resource
      unless DataScript::Constraints.has_headcircum(results)
        headcircum_resource = FHIR::Observation.new({
          id: SecureRandom.uuid,
          meta: {
            profile: [
              'http://hl7.org/fhir/StructureDefinition/vitalsigns',
              'http://hl7.org/fhir/us/core/StructureDefinition/head-occipital-frontal-circumference-percentile'
            ]
          },
          category: [
            {
              coding: [
                {
                  code: 'vital-signs',
                  system: 'http://terminology.hl7.org/CodeSystem/observation-category',
                  display: 'Vital Signs'
                }
              ]
            }
          ],
          code: {
            coding: [
              {
                code: '8289-1',
                system: 'http://loinc.org',
                display: 'Head Occipital-frontal circumference Percentile'
              }
            ]
          },
          subject: {
            reference: "urn:uuid:#{DataScript::Constraints.patient(results.first).id}"
          },
          status: 'final',
          effectiveDateTime: (DateTime.strptime(DataScript::Constraints.patient(results.first).birthDate, '%Y-%m-%d') + 30).iso8601,
          valueQuantity: {
            value: 23,
            unit: '%',
            system: 'http://unitsofmeasure.org',
            code: '%'
          }
        })
        results.first.entry.push create_bundle_entry(headcircum_resource)
        provenance = results.first.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
        provenance.target << FHIR::Reference.new
        provenance.target.last.reference = "urn:uuid:#{headcircum_resource.id}"
      end

      puts "  - Processing Observation Data Absent Reasons"
      results.each do |bundle|
        provenance = bundle.entry.find { |e| e.resource.is_a? FHIR::Provenance }.resource
        break if observation_profiles.empty?
        observation_profiles.delete_if do |profile_url|
          entry = bundle.entry.find {|e| e.resource.resourceType == 'Observation' && e.resource.meta&.profile&.include?(profile_url) }
          if entry
            instance = FHIR::Json.from_json(entry.resource.to_json)
            instance.id = SecureRandom.uuid
            instance.dataAbsentReason = create_codeable_concept('http://terminology.hl7.org/CodeSystem/data-absent-reason', 'unknown', 'Unknown')
            if observation_profiles_valueCodeableConcept_required.include?(profile_url)
              instance.valueCodeableConcept = instance.dataAbsentReason
              instance.dataAbsentReason = nil
            elsif observation_profiles_components_required.include?(profile_url)
              instance.component.each do |component|
                component.valueQuantity = nil
                component.dataAbsentReason = instance.dataAbsentReason
              end
            else
              instance.valueQuantity = nil
              instance.valueCodeableConcept = nil
              instance.valueString = nil
            end
            new_entry = create_bundle_entry(instance)
            provenance.target << FHIR::Reference.new
            provenance.target.last.reference = "urn:uuid:#{instance.id}"
            bundle.entry << new_entry
            puts "    - #{profile_url}: #{new_entry.fullUrl}"
            true # delete this profile url from the list
          else
            false # keep searching for this profile url in the next bundle
          end
        end
      end
      unless observation_profiles.empty?
        puts "  * Missed Observation Data Absent Reasons"
        observation_profiles.each do |profile_url|
          puts "    ** #{profile_url}"
        end
      end

      # remove all resources from bundles that are not US Core profiles
      results.each do |bundle|
        bundle.entry.delete_if {|e| ['Claim','ExplanationOfBenefit','ImagingStudy','MedicationAdministration','SupplyDelivery'].include?(e.resource.resourceType)}
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

      DataScript::ChoiceTypeCreator.check_choice_types(results)

      # DiagnosticReports need to have two performer types, so we add them here
      dr_bundle = results.find do |b|
        b.entry.any? do |e|
          e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta.profile.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-note')
        end &&
          b.entry.any? do |e|
            e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta.profile.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-lab')
          end
      end
      dr_notes = dr_bundle.entry.find_all do |e|
        e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta.profile.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-note')
      end.map {|e| e.resource }
      dr_labs = dr_bundle.entry.find_all do |e|
        e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta.profile.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-lab')
      end.map {|e| e.resource }
      dr_practitioner = dr_bundle.entry.find { |e| e.resource.is_a? FHIR::Practitioner }.resource.id
      dr_organization = dr_bundle.entry.find { |e| e.resource.is_a? FHIR::Organization }.resource.id
      puts "DR Practitioner id: #{dr_practitioner}"
      puts "DR Org ID: #{dr_organization}"
      dr_notes.concat(dr_labs).each do |dr|
        dr.performer << { reference: "urn:uuid:#{dr_practitioner}" }
        dr.performer << { reference: "urn:uuid:#{dr_organization}" }
      end

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

    def self.alter_condition(bundle, rng)
      # randomly pick one of their Conditions
      random_condition = bundle.entry.map {|e| e.resource }.select {|r| r.resourceType == 'Condition'}.sample(random: rng)
      # and replace the category with a data-absent-reason
      unknown = FHIR::CodeableConcept.new
      unknown.extension = [ data_absent_reason ]
      random_condition.category = [ unknown ]
      random_condition
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

    def self.create_codeable_concept(system, code, display)
      coding = FHIR::Coding.new
      coding.system = system
      coding.display = display
      coding.code = code
      codeableconcept = FHIR::CodeableConcept.new
      codeableconcept.text = display
      codeableconcept.coding = [ coding ]
      codeableconcept
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

    def self.get_resource_counts(bundle)
      resource_counts = bundle.entry.each_with_object({}) do |entry, rc|
        resource_type = entry.resource.resourceType
        if rc[resource_type]
          rc[resource_type] += 1
        else
          rc[resource_type] = 1
        end
      end.sort
      # Move DocumentReferences to the front, so we delete them first (and don't have reference issues)
      resource_counts.insert(0, resource_counts.delete(resource_counts.find { |resource_name, _| resource_name == 'DocumentReference' }))
      # Move Encounters to the end, so we know which ones are safe to delete
      resource_counts.append(resource_counts.delete(resource_counts.find { |resource_name, _| resource_name == 'Encounter' }))
      resource_counts
    end

    def self.get_diagreport_referenced_observations(bundle)
      bundle.entry.flat_map do |entry|
        next unless entry.resource.is_a? FHIR::DiagnosticReport
        entry.resource.result.map { |r| r&.reference&.split(':')&.last }
      end.uniq.compact
    end

    def self.get_docref_referenced_attachments(bundle)
      docrefs = bundle.entry.find_all { |e| e.resource.is_a? FHIR::DocumentReference}
      docrefs.map do |docref|
        bundle.entry.reverse.find { |e|
          e&.resource&.resourceType == 'DiagnosticReport' &&
            e&.resource&.presentedForm&.first&.data &&
            e&.resource&.presentedForm&.first&.data == docref&.resource&.content&.first&.attachment&.data }&.resource&.id
      end.uniq
    end

    def self.get_referenced_encounters(bundle)
      bundle.entry.map do |e|
        e.resource&.encounter&.reference&.split(':')&.last if e.resource.respond_to? :encounter
      end.compact.uniq
    end

    def self.get_referenced_reasons(bundle)
      bundle.entry.flat_map do |e|
        e.resource&.reasonReference&.map { |r| r.reference.split(':')&.last } if e.resource.respond_to? :reasonReference
      end.compact.uniq
    end

    def self.get_addresses(bundle)
      bundle.entry.flat_map do |e|
        e.resource&.addresses&.map { |r| r.reference.split(':')&.last } if e.resource.respond_to? :addresses
      end.compact.uniq
    end

    def self.get_medreqs_with_med_references(bundle)
      bundle.entry.select { |e| e.resource.is_a? FHIR::MedicationRequest }.flat_map do |e|
        if e.resource&.medicationReference
          [e.resource.id, e&.resource&.medicationReference&.reference&.split(':')&.last]
        end
      end.compact.uniq
    end

    def self.remove_provenance_targets(ids, provenance)
      ids.each do |id|
        provenance.target.delete_if { |target| target.id == id }
      end
    end
  end
end
