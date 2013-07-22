module ActiveMerchant
  module Shipping
    class DHL < Carrier
      cattr_reader :name
      @@name = "DHL"
      
      API_VERSION = 'v1'
      LIVE_URL = 'http:/api.dhlglobalmail.com/' + API_VERSION
      TEST_URL = 'http://apitest.dhlglobalmail.com/' + API_VERSION

      RESOURCES = {
        # :rates => 'ups.app/xml/Rate',
        # :track => 'ups.app/xml/Track',
        :label => 'label/US/CUSTOMER_ID/image.xml',
        :return  => 'label/generate_return.xml',
        :auth => 'auth/access_token.xml'
      }

      US_SERVICES = {
        "76"=>"SM BPM Expedited", 
        "77"=>"SM BPM Ground", 
        "72"=>"SM Flats Expedited", 
        "73"=>"SM Flats Ground", 
        "384"=>"SM Marketing Parcel Expedited", 
        "383"=>"SM Marketing Parcel Ground", 
        "80"=>"SM Media Mail Ground", 
        "36"=>"SM Parcel Plus Expedited", 
        "83"=>"SM Parcel Plus Ground", 
        "81"=>"SM Parcels Expedited", 
        "82"=>"SM Parcels Ground"
      }

      INTL_SERVICES = {
        "43"=>"GM Business Canada Lettermail", 
        "41"=>"GM Business IPA", 
        "42"=>"GM Business ISAL", 
        "34"=>"GM Business Priority", 
        "35"=>"GM Business Standard", 
        "46"=>"GM Direct Canada Admail", 
        "44"=>"GM Direct Priority", 
        "45"=>"GM Direct Standard", 
        "69"=>"GM Others (International)", 
        "29"=>"GM Packet Plus", 
        "58"=>"GM Parcel Canada Parcel Priority", 
        "59"=>"GM Parcel Canada Parcel Standard", 
        "54"=>"GM Parcel Priority", 
        "60"=>"GM Parcel Priority Track and Trace", 
        "55"=>"GM Parcel Standard", 
        "51"=>"GM Publication Canada Publication", 
        "47"=>"GM Publication Priority", 
        "48"=>"GM Publication Standard"
      } 

      SERVICES = US_SERVICES.merge(INTL_SERVICES) 

      FACILITIES = {
        "USATL1"=>"Forest Park, GA", 
        "USBOS1"=>"Franklin, MA", 
        "USBWI1"=>"Elkridge, MD", 
        "USCVG1"=>"Hebron, KY", 
        "USDEN1"=>"Denver, CO", 
        "USDFW1"=>"Grand Prairie, TX", 
        "USEWR1"=>"Secaucus, NJ", 
        "USISP1"=>"Edgewood, NY", 
        "USLAX1"=>"Compton, CA", 
        "USMCO1"=>"Orlando, FL", 
        "USMEM1"=>"Memphis, TN", 
        "USORD1"=>"Des Plaines, IL", 
        "USPHX1"=>"Phoenix, AZ", 
        "USSEA1"=>"Auburn, WA", 
        "USSFO1"=>"Union City, CA", 
        "USSLC1"=>"Salt Lake City, UT", 
        "USSTL1"=>"St. Louis, MO"
      }

      MAIL_TYPES = {
        "2"=>"Irregular Parcel", 
        "3"=>"Machinable Parcel", 
        "6"=>"BPM Machinable", 
        "7"=>"Parcel Select Mach", 
        "8"=>"Parcel Select NonMach", 
        "9"=>"Media Mail", 
        "20"=>"Marketing Parcel < 6oz", 
        "30"=>"Marketing Parcel >= 6oz"
      }

      def requirements
        [:username, :password, :client_id, :customer_id]
      end

      # def find_rates(origin, destination, packages, options = {})
      #   origin = Location.from(origin)
      #   destination = Location.from(destination)
      #   packages = Array(packages)
      # end

      def get_label(origin, destination, package, options={})
        options = @options.merge(options)

        auth_response = ssl_get("http://apitest.dhlglobalmail.com/v1/auth/access_token?username=whiplash.tester&password=wh1pl4sh")
        parsed_auth_response = ActiveSupport::JSON.decode(auth_response)
        if parsed_auth_response['data'] and parsed_auth_response['data']['access_token']
          options[:access_token] = parsed_auth_response['data']['access_token']
        else
          raise ArgumentError.new("Couldn't fetch access token.")
        end
     puts "ACCESS TOKEN: " + options[:access_token].inspect   
        label_request = build_label_request(origin, destination, package, options)
    puts "LABEL REQUEST: " + label_request.inspect
        response = commit(:label, save_request(label_request), (options[:test] || false), options)
    puts "RESPONSE: " + response.inspect
        parse_label_response(origin, destination, package, response, options)
      end

      protected

        def commit(action, request, test = false, options={})
          # TODO: options error checking
          url = "#{test ? TEST_URL : LIVE_URL}/#{RESOURCES[action]}?#{options[:client_id]}&access_token=#{options[:access_token]}".gsub('CUSTOMER_ID', options[:customer_id])
          ssl_post(url, request)
        end

        def build_label_request(origin, destination, package, options={})
          # @required = :batch_ref, :customer_id, :package_id, :ordered_product_code, :mail_type_code, :facility_code

          # @package += :weight, :unit, :value

          # @destination +=  [:address1, :city, :state, :zip]
          # @origin +=  [:address1, :city, :state, :zip]

          missing_required = Array.new
          errors = Array.new

          ship_date = options[:expected_ship_date] ? Date.parse(options[:expected_ship_date]).strftime("%Y%m%d") : Time.now.strftime("%Y%m%d")

          xml_request = XmlNode.new('EncodeRequest') do |request|
            request << XmlNode.new('CustomerId', options[:customer_id])
            # NOTE: BatchRef is required, but will be deprecated soon
            # it just needs a string at the moment
            request << XmlNode.new('BatchRef', 'xxx')
            request << XmlNode.new('HaltOnError', false)
            request << XmlNode.new('RejectAllOnError', true)
            request << XmlNode.new('MpuList') do |mpu_list|
              mpu_list << XmlNode.new('Mpu') do |mpu|
                # package
                mpu << XmlNode.new('PackageId', options[:package_id])

                # there's only a package ref if we have passed in label_text
                unless options[:label_text].blank?
                  mpu << XmlNode.new('PackageRef') do |package_ref|
                    package_ref << XmlNode.new('PrintFlag', true)
                    package_ref << XmlNode.new('LabelText', options[:label_text])
                  end
                end

                #destination
                destination.address2 = '' if destination.address2.blank?
                destination.country_code = 'US' if destination.country_code.blank?
                mpu << XmlNode.new('ConsigneeAddress') do |consignee|
                  consignee << build_location_node('StandardAddress', destination, options)
                end

                for field in %w[address1 city zip country]
                  missing_required << "ShipTo #{field}" if destination.send(field).blank?
                end

                if destination.name.blank? and destination.company_name.blank?
                  missing_required << "ShipTo name or company_name"
                end

                # TODO: At the moment, this is US shipping only
                # # State/Province is only required for US/Canada
                # if !%w[GB US].include? destination.country_code(:alpha2)
                #   missing_required << "ShipTo #{field}" if destination.send(field).blank?
                # end

                # origin
                origin.address2 = '' if origin.address2.blank?
                origin.country_code = 'US' if origin.country_code.blank?
                mpu << XmlNode.new('ReturnAddress') do |consignee|
                  consignee << build_location_node('StandardAddress', origin, options)
                end

                for field in %w[address1 name city zip country]
                  missing_required << "ShipFrom #{field}" if origin.send(field).blank?
                end

                if origin.name.blank? and origin.company_name.blank?
                  missing_required << "ShipFrom name or company_name"
                end

                mpu << XmlNode.new('OrderedProductCode', SERVICES.invert(options[:service]))

                mpu << XmlNode.new("Weight") do |weight|
                  weight << XmlNode.new("Unit", imperial ? 'LBS' : 'KGS')
                
                  value = ((imperial ? package.lbs : package.kgs).to_f*1000).round/1000.0 # 3 decimals
                  weight << XmlNode.new("Value", [value,0.1].max)
                end

                # TODO: What the fuck is service?
                # mpu << XmlNode.new('Service', SERVICES.invert(options[:service]))
                
                unless options[:billing_ref1].blank?
                  mpu << XmlNode.new('BillingRef1', options[:billing_ref1])
                  mpu << XmlNode.new('BillingRef2', options[:billing_ref2]) unless options[:billing_ref2].blank?
                end

                # TODO: Is there a good default to use here?
                mpu << XmlNode.new('MailTypeCode', MAIL_TYPES.invert(options[:mail_type]))
                mpu << XmlNode.new('FacilityCode', FACILITIES.invert(options[:facility]))
                mpu << XmlNode.new('ExpectedShipDate', ship_date)

              end
            end
          end # end Label request XML

          # There are a lot of required fields for the label request to work
          # We collect them all in one error, so it doesn't take folks 20 tries to construct a working request
          errors << "DHL labels require: #{missing_required.join(', ')}" if missing_required.length > 0

          # Now we spit out all of the errors; 
          # We don't even want to make the request if we know it won't go through
          raise ArgumentError.new(errors.join('; ')) if errors.length > 0

          xml_request.to_s
        end # end build label request

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

    end # end Class
  end
end

# curl -v -X POST -d "" http://api.dhlglobalmail.com/v1/label/US/5300000/image.xml?access_token=7oQf6biOy0x0f2yLURKdw1C1LlVy7zoA+jz6zZgOd7A+bQPTF80+nJiYoEWCdFQUQQW3wv4jQx8WNrGd2JEAEXYSrip77np4F7X2icSxAgorjRdabr7d1jjktOI1Z448HitmxciYbkXfKDYuS6Pqxg==&client_id=whiplash.track 

# <?xml version="1.0"?>
# <EncodeRequest>
#   <CustomerId>5300000</CustomerId>
#   <BatchRef>1346421550190</BatchRef>
#   <HaltOnError>false</HaltOnError>
#   <RejectAllOnError>true</RejectAllOnError>
#   <MpuList>
#     <Mpu>
#       <PackageId>13464215501902</PackageId>
#       <PackageRef>
#         <PrintFlag>true</PrintFlag>
#         <LabelText>ABC</LabelText>
#       </PackageRef>

#       <ConsigneeAddress>
#         <StandardAddress>
#           <Name>Joe Bloggs</Name>
#           <Firm></Firm>
#           <Address1>1234 Main Street</Address1>
#           <Address2></Address2>
#           <City>Anytown</City>
#           <State>GA</State>
#           <Zip>30297</Zip>
#           <CountryCode>US</CountryCode>
#         </StandardAddress>
#       </ConsigneeAddress>

#       <ReturnAddress>
#         <StandardAddress>
#           <Name>Mr. Returns</Name>
#           <Firm></Firm>
#           <Address1>1500 South Point Dr.</Address1>
#           <Address2></Address2>
#           <City>Forrest Park</City>
#           <State>GA</State>
#           <Zip>30297</Zip>
#           <CountryCode>US</CountryCode>
#         </StandardAddress>
#       </ReturnAddress>

#       <OrderedProductCode>81</OrderedProductCode>
#       <Weight>
#         <Value>0.276</Value>
#         <Unit>LB</Unit>
#       </Weight>
#       <Service>DELCON</Service>
#       <BillingRef1></BillingRef1>
#       <BillingRef2></BillingRef2>
#       <MailTypeCode>7</MailTypeCode>
#       <FacilityCode>USATL1</FacilityCode>
#       <ExpectedShipDate>20130301</ExpectedShipDate>
#     </Mpu>
#   </MpuList>
# </EncodeRequest>