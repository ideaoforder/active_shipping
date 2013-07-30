# body = "labelRequestXML=<LabelRequest><AccountID>792190</AccountID><RequesterID>vgtest</RequesterID><PassPhrase>whiplash1</PassPhrase><Test>YES</Test><FromAddress1>4657 Platt Road</FromAddress1><FromCity>Ann Arbor</FromCity><FromState>MI</FromState><FromPostalCode>48108</FromPostalCode><FromCompany>Indie Game The Movie</FromCompany><FromPhone>7344800667</FromPhone><ToPostalCode>97204</ToPostalCode><ToName>Ron Chan</ToName><ToEMail>rondanchan@gmail.com</ToEMail><ToPhone></ToPhone><ToAddress1>333 SW 5th Ave</ToAddress1><ToAddress2>Ste 500</ToAddress2><ToCity>Portland</ToCity><ToState>Oregon</ToState><ToCountry>United States</ToCountry><PartnerTransactionID>37469</PartnerTransactionID><PartnerCustomerID>232</PartnerCustomerID><MailClass>FIRST</MailClass><WeightOz>7</WeightOz><Value>69.99</Value><PackageType>RECTPARCEL</PackageType><ReturnAddress1>Indie Game The Movie</ReturnAddress1><ReturnAddress2>Distribution</ReturnAddress2><ReturnAddress3>4657 Platt Road</ReturnAddress3><ReturnAddress4>Ann Arbor, MI 48108</ReturnAddress4><ReturnAddressPhone>7344800667</ReturnAddressPhone><IntegratedFormType>Form2976</IntegratedFormType><CustomsCertify>TRUE</CustomsCertify><CustomsSigner>James Marks</CustomsSigner><CustomsInfo><ContentsType>MERCHANDISE</ContentsType><CustomsItems><CustomsItem><Quantity>1</Quantity><Description>Special Edition BLURAY, Indie Game: The Movie, Special Ed.  BLURAY</Description><Value>69.99</Value><CountryOfOrigin>US</CountryOfOrigin><Weight>1</Weight></CustomsItem></CustomsItems></CustomsInfo></LabelRequest>"
# -*- encoding: utf-8 -*-

module ActiveMerchant
  module Shipping
    class Endicia < Carrier
      require 'tempfile'
      self.retry_safe = true
      
      cattr_accessor :default_options
      cattr_reader :name
      @@name = "Endicia"
      
      TEST_URL = 'https://www.envmgr.com'
      LIVE_URL = 'https://www.envmgr.com'

    # return Endicia::Label.new(result["LabelRequestResponse"])
      
      RESOURCES = {
        :label => 'LabelService/EwsLabelService.asmx/GetPostageLabelXML'
        # :void  => 'ups.app/xml/Void'
      }
      
      def requirements
        [:account_id, :requester_id, :password]
      end
      
      def get_label(origin, destination, packages, options={})
        options = @options.merge(options)
        packages = Array(packages)
        package = packages.first # For the moment, let's get one package working
        
        label_request = build_label_request(origin, destination, package, options)
        puts label_request.inspect
        response = commit(:label, save_request(label_request), (options[:test] || false))
        puts response.inspect
        # parse_label_response(origin, destination, packages, response, options)
      end

      # def void_label(shipping_id, tracking_numbers=[], options={})
      #   access_request = build_access_request
      #   void_request = build_void_request(shipping_id, tracking_numbers)
      #   # NOTE: For some reason, this request requires the xml version
      #   req = '<?xml version="1.0"?>' + access_request + '<?xml version="1.0"?>' + void_request
      #   response = commit(:void, save_request(req), (options[:test] || false))
      #   parse_void_response(response, tracking_numbers)
      # end
      
      protected
      
      # See Ship-WW-XML.pdf for API info
       # @image_type = [GIF|EPL] 
      def build_label_request(origin, destination, package, options={})
        # @required = :origin_account, 
        # @destination +=  [:phone, :email, :company, :address, :city, :state, :zip]
        # @shipper += [:sender_phone, :sender_email, :sender_company, :sender_address, :sender_city, :sender_state, :sender_zip ]
        missing_required = Array.new
        errors = Array.new

        # pickup_date = options[:pickup_date] ? Date.parse(options[:pickup_date]).strftime("%Y%m%d") : Time.now.strftime("%Y%m%d")
        # if options[:adult_signature_required]
        #   options[:delivery_confirmation] = '1'
        # elsif options[:signature_required]
        #   options[:delivery_confirmation] = '2'
        # elsif options[:delivery_confirmation]
        #   options[:delivery_confirmation] = '3'
        # else
        #   options[:delivery_confirmation] = false
        # end

        xml_request = XmlNode.new('LabelRequest') do |root_node|
        	# Account stuff
          root_node << XmlNode.new('AccountID', options[:account_id])
          root_node << XmlNode.new('RequesterID', options[:requester_id])
          root_node << XmlNode.new('PassPhrase', options[:password])
          root_node << XmlNode.new('Test', options[:test] || false)

          # Order level stuff
          root_node << XmlNode.new('PartnerTransactionID', options[:transaction_id])
          root_node << XmlNode.new('PartnerCustomerID', options[:customer_id])
          root_node << XmlNode.new('MailClass', options[:service_type]) # TODO: May need something to help format/determine this

          # From
          for field in %w[state city zip address1]
            missing_required << "ShipFrom #{field}" if origin.send(field).blank?
          end
          root_node << XmlNode.new('FromName', origin.name)
          root_node << XmlNode.new('FromCity', origin.city)
          root_node << XmlNode.new('FromState', origin.state)
          root_node << XmlNode.new('FromPostalCode', origin.zip) # TODO: Strip this zip for domestic?
          root_node << XmlNode.new('FromCompany', origin.company)
          root_node << XmlNode.new('FromPhone', origin.phone)
          root_node << XmlNode.new('FromEmail', origin.email)
          root_node << XmlNode.new('ReturnAddress1', origin.address1)
          root_node << XmlNode.new('ReturnAddress2', origin.address2) unless origin.address2.blank? 
          root_node << XmlNode.new('ReturnAddress3', origin.address3) unless origin.address3.blank?
          root_node << XmlNode.new('FromCountry', origin.country) unless destination.country_code(:alpha2) == 'US'

          # To
          for field in %w[state city zip address1]
            missing_required << "ShipFrom #{field}" if destination.send(field).blank?
          end
          root_node << XmlNode.new('ToName', destination.name)
          root_node << XmlNode.new('ToCity', destination.city)
          root_node << XmlNode.new('ToState', destination.state)
          root_node << XmlNode.new('ToPostalCode', destination.zip) # TODO: Strip this zip for domestic?
          root_node << XmlNode.new('ToCompany', destination.company)
          root_node << XmlNode.new('ToPhone', destination.phone)
          root_node << XmlNode.new('ToEmail', destination.email)
          root_node << XmlNode.new('ToAddress1', destination.address1)
          root_node << XmlNode.new('ToAddress2', destination.address2) unless destination.address2.blank? 
          root_node << XmlNode.new('ToAddress3', destination.address3) unless destination.address3.blank?
          root_node << XmlNode.new('ToCountryCode', destination.country_code(:alpha2)) unless destination.country_code(:alpha2) == 'US'


	        # Package stuff
	        root_node << XmlNode.new('WeightOz', package.weight) # TODO: Need to format this
	        root_node << XmlNode.new('Value', package.value)
	        root_node << XmlNode.new('PackageType', options[:package_type])
	        # :MailpieceShape => self.package_type

	        # Customs stuff
	        if options[:customs]
						root_node << XmlNode.new('IntegratedFormType', options[:customs][:form_type]) unless options[:customs][:form_type].blank?
						root_node << XmlNode.new('CustomsCertify', (options[:customs][:certify] and options[:customs][:certify] == false) ? 'FALSE' : 'TRUE')
						root_node << XmlNode.new('CustomsSigner', options[:customs][:signer]) unless options[:customs][:signer].blank?
						root_node << XmlNode.new('CustomsInfo') do |customs|

							customs << XmlNode.new('ContentsType', options[:customs][:contents_type]) unless options[:customs][:contents_type].blank?

							if options[:customs][:items] and options[:customs][:items].length > 0
								customs << XmlNode.new('CustomsItems') do |customs_items|
									for item in options[:customs][:items]
										customs_items << XmlNode.new('CustomsItem') do |customs_item|
											customs_item << XmlNode.new('Quantity', item[:quantity])
											customs_item << XmlNode.new('Value', item[:value])
											customs_item << XmlNode.new('Weight', item[:weight])
											customs_item << XmlNode.new('Description', item[:description])
											customs_item << XmlNode.new('CountryOfOrigin', item[:country])
										end
									end
								end
							end
						end
	        end

	      end
        # There are a lot of required fields for the label request to work
        # We collect them all in one error, so it doesn't take folks 20 tries to construct a working request
        errors << "USPS labels require: #{missing_required.join(', ')}" if missing_required.length > 0

        # Now we spit out all of the errors; 
        # We don't even want to make the request if we know it won't go through
        raise ArgumentError.new(errors.join('; ')) if errors.length > 0

        return "labelRequestXML=#{xml_request.to_s}"
      end      

      # # This voids a shipment
      # # if multiple tracking numbers are passed in, it will attempt to void them all in a single call
      # # if ANY of them fails, we return false and hand over the array of results
      # def build_void_request(shipping_id, tracking_numbers = [])
      #   xml_request = XmlNode.new('VoidShipmentRequest') do |root_node|
      #     root_node << XmlNode.new('Request') do |request|
      #       request << XmlNode.new('RequestAction', 'Void')
      #       request << XmlNode.new('TransactionReference') do |ref|
      #         ref << XmlNode.new('CustomerContext', "Void Label")
      #       end
      #     end
      #     if tracking_numbers.length > 1
      #       root_node << XmlNode.new('ExpandedVoidShipment') do |evs|
      #         evs << XmlNode.new('RequestAction', 'Void')
      #         evs << XmlNode.new('ShipmentIdentificationNumber', shipping_id)
      #         for num in tracking_numbers
      #           evs << XmlNode.new('TrackingNumber', num)
      #         end
      #       end
      #     else
      #       root_node << XmlNode.new('ShipmentIdentificationNumber', shipping_id)
      #     end
      #   end
      #   xml_request.to_s
      # end
      
      def parse_label_response(origin, destination, packages, response, options={})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        
        if success
          package_labels = []
          xml.elements.each('//ShipmentAcceptResponse/ShipmentResults/PackageResults') do |package_element|
            package_labels << {}
            package_labels.last[:tracking_number] = package_element.get_text("TrackingNumber").to_s
            package_labels.last[:encoded_label] = package_element.get_text("LabelImage/GraphicImage")
            extension = package_element.get_text("LabelImage/LabelImageFormat/Code").to_s
            package_labels.last[:label_file] = Tempfile.new(["shipping_label_#{Time.now}_#{Time.now.usec}", '.' + extension.downcase], :encoding => 'ascii-8bit')
            package_labels.last[:label_file].write Base64.decode64( package_labels.last[:encoded_label].value )
            package_labels.last[:label_file].rewind
            
            # if this package has a high insured value
            high_value_report = package_element.get_text("//ShipmentAcceptResponse/ShipmentResults/ControlLogReceipt/GraphicImage")
            if high_value_report
              extension = package_element.get_text("//ShipmentAcceptResponse/ShipmentResults/ControlLogReceipt/ImageFormat/Code")
              package_labels.last[:encoded_high_value_report] = high_value_report
              package_labels.last[:high_value_report] = Tempfile.new(["high_value_report", '.' + extension.downcase], :encoding => 'ascii-8bit')
              package_labels.last[:high_value_report].write Base64.decode64( package_labels.last[:encoded_high_value_report].value )
              package_labels.last[:high_value_report].rewind
            end
          end
        end
        LabelResponse.new(success, message, Hash.from_xml(response).values.first, :package_labels => package_labels)
      end

    # def parse_void_response(response, tracking_numbers=[])
    #   xml = REXML::Document.new(response)
    #   success = response_success?(xml)
    #   message = response_message(xml)

    #   if tracking_numbers.length > 1
    #     status = true
    #     multiple_response = Hash.new
    #     xml.elements.each('//VoidShipmentResponse/PackageLevelResults') do |package_element|
    #       tracking_number = package_element.get_text("TrackingNumber").to_s
    #       response_code = package_element.get_text("StatusCode/Code").to_i
    #       multiple_response[tracking_number] = response_code
    #       status = false if response_code != 1
    #     end
    #     if status == true
    #       return true
    #     else
    #       return multiple_response
    #     end
    #   else
    #     status = xml.get_text('//VoidShipmentResponse/Response/ResponseStatusCode').to_s
    #     # TODO: we may need a more detailed error message in the event that one package is voided and the other isn't
    #     if status == '1'
    #       return true
    #     else
    #       return message
    #     end
    #   end
    # end


    	def strip_zip(zip)
        zip.to_s.scan(/\d{5}/).first || zip
      end

      def response_success?(xml)
        xml.get_text('/*/Response/ResponseStatusCode').to_s == '1'
      end
      
      def response_message(xml)
        xml.get_text('/*/Response/Error/ErrorDescription | /*/Response/ResponseStatusDescription').to_s
      end
      
      def commit(action, request, test = false)
        ssl_post("#{test ? TEST_URL : LIVE_URL}/#{RESOURCES[action]}", request)
      end
      
    end
  end
end
