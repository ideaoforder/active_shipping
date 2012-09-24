# -*- encoding: utf-8 -*-

module ActiveMerchant
  module Shipping
    class UPS < Carrier
      self.retry_safe = true
      
      cattr_accessor :default_options
      cattr_reader :name
      @@name = "UPS"
      
      TEST_URL = 'https://wwwcie.ups.com'
      LIVE_URL = 'https://onlinetools.ups.com'
      
      RESOURCES = {
        :rates => 'ups.app/xml/Rate',
        :track => 'ups.app/xml/Track',
        :time => 'ups.app/xml/TimeInTransit',
        :label => 'ups.app/xml/ShipConfirm'
      }
      
      PICKUP_CODES = HashWithIndifferentAccess.new({
        :daily_pickup => "01",
        :customer_counter => "03", 
        :one_time_pickup => "06",
        :on_call_air => "07",
        :suggested_retail_rates => "11",
        :letter_center => "19",
        :air_service_center => "20"
      })

      CUSTOMER_CLASSIFICATIONS = HashWithIndifferentAccess.new({
        :wholesale => "01",
        :occasional => "03", 
        :retail => "04"
      })
      
      PAYMENT_TYPES = HashWithIndifferentAccess.new({
        :prepaid => 'Prepaid',
        :consignee => 'Consignee', # TODO: Implement
        :bill_third_party => 'BillThirdParty',
        :freight_collect => 'FreightCollect'
      })

      # these are the defaults described in the UPS API docs,
      # but they don't seem to apply them under all circumstances,
      # so we need to take matters into our own hands
      DEFAULT_CUSTOMER_CLASSIFICATIONS = Hash.new do |hash,key|
        hash[key] = case key.to_sym
        when :daily_pickup then :wholesale
        when :customer_counter then :retail
        else
          :occasional
        end
      end
      
      DEFAULT_SERVICES = {
        "01" => "UPS Next Day Air",
        "02" => "UPS Second Day Air",
        "03" => "UPS Ground",
        "07" => "UPS Worldwide Express",
        "08" => "UPS Worldwide Expedited",
        "11" => "UPS Standard",
        "12" => "UPS Three-Day Select",
        "13" => "UPS Next Day Air Saver",
        "14" => "UPS Next Day Air Early A.M.",
        "54" => "UPS Worldwide Express Plus",
        "59" => "UPS Second Day Air A.M.",
        "65" => "UPS Saver",
        "82" => "UPS Today Standard",
        "83" => "UPS Today Dedicated Courier",
        "84" => "UPS Today Intercity",
        "85" => "UPS Today Express",
        "86" => "UPS Today Express Saver"
      }
      
      CANADA_ORIGIN_SERVICES = {
        "01" => "UPS Express",
        "02" => "UPS Expedited",
        "14" => "UPS Express Early A.M."
      }
      
      MEXICO_ORIGIN_SERVICES = {
        "07" => "UPS Express",
        "08" => "UPS Expedited",
        "54" => "UPS Express Plus"
      }
      
      EU_ORIGIN_SERVICES = {
        "07" => "UPS Express",
        "08" => "UPS Expedited"
      }
      
      OTHER_NON_US_ORIGIN_SERVICES = {
        "07" => "UPS Express"
      }

      TRACKING_STATUS_CODES = HashWithIndifferentAccess.new({
        'I' => :in_transit,
        'D' => :delivered,
        'X' => :exception,
        'P' => :pickup,
        'M' => :manifest_pickup
      })

      # From http://en.wikipedia.org/w/index.php?title=European_Union&oldid=174718707 (Current as of November 30, 2007)
      EU_COUNTRY_CODES = ["GB", "AT", "BE", "BG", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"]
      
      US_TERRITORIES_TREATED_AS_COUNTRIES = ["AS", "FM", "GU", "MH", "MP", "PW", "PR", "VI"]
      
      def requirements
        [:key, :login, :password]
      end
      
      def find_rates(origin, destination, packages, options={})
        origin, destination = upsified_location(origin), upsified_location(destination)
        options = @options.merge(options)
        packages = Array(packages)
        access_request = build_access_request
        rate_request = build_rate_request(origin, destination, packages, options)
        response = commit(:rates, save_request(access_request + rate_request), (options[:test] || false))
        parse_rate_response(origin, destination, packages, response, options)
      end
      
      def find_tracking_info(tracking_number, options={})
        options = @options.update(options)
        access_request = build_access_request
        tracking_request = build_tracking_request(tracking_number, options)
        response = commit(:track, save_request(access_request + tracking_request), (options[:test] || false))
        parse_tracking_response(response, options)
      end
      
      def find_transit_time(origin, destination, packages, options={})
        origin, destination = upsified_location(origin), upsified_location(destination)
        options = @options.merge(options)
        packages = Array(packages)
        access_request = '<?xml version="1.0" encoding="UTF-8"?>' + build_access_request
        transit_time_request = '<?xml version="1.0" encoding="UTF-8"?>' + build_transit_time_request(origin, destination, packages, options)
        req = access_request + transit_time_request
        puts req.to_s
        response = commit(:time, save_request(req), (options[:test] || false))
        parse_transit_time_response(origin, destination, packages, response, options)
      end
      
      def get_label(origin, destination, packages, options={})
        origin, destination = upsified_location(origin), upsified_location(destination)
        options = @options.merge(options)
        packages = Array(packages)
        access_request = build_access_request
        
        label_request = build_label_request(origin, destination, packages, options)
        req = access_request + label_request
        puts req.to_s
        response = commit(:rates, save_request(req), (options[:test] || true))
        parse_label_response(origin, destination, packages, response, options)
      end
      
      protected
      
      def upsified_location(location)
        if location.country_code == 'US' && US_TERRITORIES_TREATED_AS_COUNTRIES.include?(location.state)
          atts = {:country => location.state}
          [:zip, :city, :address1, :address2, :address3, :phone, :fax, :address_type].each do |att|
            atts[att] = location.send(att)
          end
          Location.new(atts)
        else
          location
        end
      end
      
      def build_access_request
        xml_request = XmlNode.new('AccessRequest') do |access_request|
          access_request << XmlNode.new('AccessLicenseNumber', @options[:key])
          access_request << XmlNode.new('UserId', @options[:login])
          access_request << XmlNode.new('Password', @options[:password])
        end
        xml_request.to_s
      end
      
      def build_rate_request(origin, destination, packages, options={})
        packages = Array(packages)
        xml_request = XmlNode.new('RatingServiceSelectionRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Rate')
            request << XmlNode.new('RequestOption', 'Shop')
            # not implemented: 'Rate' RequestOption to specify a single service query
            # request << XmlNode.new('RequestOption', ((options[:service].nil? or options[:service] == :all) ? 'Shop' : 'Rate'))
          end
          
          pickup_type = options[:pickup_type] || :daily_pickup
          
          root_node << XmlNode.new('PickupType') do |pickup_type_node|
            pickup_type_node << XmlNode.new('Code', PICKUP_CODES[pickup_type])
            # not implemented: PickupType/PickupDetails element
          end
          cc = options[:customer_classification] || DEFAULT_CUSTOMER_CLASSIFICATIONS[pickup_type]
          root_node << XmlNode.new('CustomerClassification') do |cc_node|
            cc_node << XmlNode.new('Code', CUSTOMER_CLASSIFICATIONS[cc])
          end
          
          root_node << XmlNode.new('Shipment') do |shipment|
            # not implemented: Shipment/Description element
            shipment << build_location_node('Shipper', (options[:shipper] || origin), options)
            shipment << build_location_node('ShipTo', destination, options)
            if options[:shipper] and options[:shipper] != origin
              shipment << build_location_node('ShipFrom', origin, options)
            end
            
            # not implemented:  * Shipment/ShipmentWeight element
            #                   * Shipment/ReferenceNumber element                    
            #                   * Shipment/Service element                            
            #                   * Shipment/PickupDate element                         
            #                   * Shipment/ScheduledDeliveryDate element              
            #                   * Shipment/ScheduledDeliveryTime element              
            #                   * Shipment/AlternateDeliveryTime element              
            #                   * Shipment/DocumentsOnly element                      
            
            packages.each do |package|
              imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))
              
              shipment << XmlNode.new("Package") do |package_node|
                
                # not implemented:  * Shipment/Package/PackagingType element
                #                   * Shipment/Package/Description element
                
                package_node << XmlNode.new("PackagingType") do |packaging_type|
                  packaging_type << XmlNode.new("Code", '02')
                end
                
                package_node << XmlNode.new("Dimensions") do |dimensions|
                  dimensions << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'IN' : 'CM')
                  end
                  [:length,:width,:height].each do |axis|
                    value = ((imperial ? package.inches(axis) : package.cm(axis)).to_f*1000).round/1000.0 # 3 decimals
                    dimensions << XmlNode.new(axis.to_s.capitalize, [value,0.1].max)
                  end
                end
              
                package_node << XmlNode.new("PackageWeight") do |package_weight|
                  package_weight << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'LBS' : 'KGS')
                  end
                  
                  value = ((imperial ? package.lbs : package.kgs).to_f*1000).round/1000.0 # 3 decimals
                  package_weight << XmlNode.new("Weight", [value,0.1].max)
                end
              
                # not implemented:  * Shipment/Package/LargePackageIndicator element
                #                   * Shipment/Package/ReferenceNumber element
                #                   * Shipment/Package/PackageServiceOptions element
                #                   * Shipment/Package/AdditionalHandling element  
              end
              
            end
            
            # not implemented:  * Shipment/ShipmentServiceOptions element
            #                   * Shipment/RateInformation element
            
          end
          
        end
        xml_request.to_s
      end
      
      def build_tracking_request(tracking_number, options={})
        xml_request = XmlNode.new('TrackRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Track')
            request << XmlNode.new('RequestOption', '1')
          end
          root_node << XmlNode.new('TrackingNumber', tracking_number.to_s)
        end
        xml_request.to_s
      end
      
      def build_transit_time_request(origin, destination, packages, options={})
        packages = Array(packages)
        shipper_city = options[:shipper][:city] if options[:shipper] and options[:shipper][:city]
        shipper_state = options[:shipper][:state] if options[:shipper] and options[:shipper][:state]
        shipper_country = options[:shipper][:country] if options[:shipper] and options[:shipper][:country]
        shipper_zip = options[:shipper][:zip] if options[:shipper] and options[:shipper][:zip]
        pickup_date = options[:pickup_date] ? Date.parse(options[:pickup_date]).strftime("%Y%m%d") : Time.now.strftime("%Y%m%d")
        
        xml_request = XmlNode.new('TimeInTransitRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'TimeInTransit')
          end
          
          root_node << XmlNode.new('CustomerContext', 'Time in Transit Request')
          # NOTE: TimeInTransit is only supported in XPCI 1.0001
          root_node << XmlNode.new('XpciVersion', '1.0001')

          # pickup_type = options[:pickup_type] || :daily_pickup
          # 
          # root_node << XmlNode.new('PickupType') do |pickup_type_node|
          #   pickup_type_node << XmlNode.new('Code', PICKUP_CODES[pickup_type])
          #   # not implemented: PickupType/PickupDetails element
          # end
          # cc = options[:customer_classification] || DEFAULT_CUSTOMER_CLASSIFICATIONS[pickup_type]
          # root_node << XmlNode.new('CustomerClassification') do |cc_node|
          #   cc_node << XmlNode.new('Code', CUSTOMER_CLASSIFICATIONS[cc])
          # end

          root_node << XmlNode.new('TransitFrom') do |from|
            from << XmlNode.new('AddressArtifactFormat') do |address|
              address << XmlNode.new('PoliticalDivision2', shipper_city || origin.city) # city
              address << XmlNode.new('PoliticalDivision1', shipper_state || origin.state) # state
              address << XmlNode.new('CountryCode', shipper_country || origin.country_code(:alpha2)) # 2 -digit country
              address << XmlNode.new('PostCodePrimaryLow', shipper_zip || origin.zip) # zip
            end
          end
          
          root_node << XmlNode.new('TransitTo') do |from|
            from << XmlNode.new('AddressArtifactFormat') do |address|
              address << XmlNode.new('PoliticalDivision2', destination.city) # city
              address << XmlNode.new('PoliticalDivision1', destination.state) # state
              address << XmlNode.new('CountryCode', destination.country_code(:alpha2)) # 2 -digit country
              address << XmlNode.new('PostCodePrimaryLow', destination.zip) # zip
              unless destination.commercial?
                address << XmlNode.new('ResidentialAddressIndicator')
              end
            end
          end
          
          root_node << XmlNode.new('PickupDate', pickup_date)
          
          root_node << XmlNode.new('ShipmentWeight') do |shipment_weight|
            imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))
            
            shipment_weight << XmlNode.new("UnitOfMeasurement") do |units|
              units << XmlNode.new("Code", imperial ? 'LBS' : 'KGS')
            end
            
            total_weight = 0.0
            packages.each do |package|
              total_weight += ((imperial ? package.lbs : package.kgs).to_f*1000).round/1000.0 # 3 decimals
            end
            shipment_weight << XmlNode.new("Weight", [total_weight,0.1].max)
          end
          
          root_node << XmlNode.new('TotalPackagesInShipment', packages.length)
          
          root_node << XmlNode.new('InvoiceLineTotal') do |invoice|
            invoice << XmlNode.new('CurrencyCode', options[:currency_code] || 'US')
            invoice << XmlNode.new('MonetaryValue', options[:insured_value] || 0)
          end

        end
        xml_request.to_s
      end
            
      # See Ship-WW-XML.pdf for API info
       # @image_type = [GIF|EPL] 
      def build_label_request(origin, destination, packages, options={})
       # @required = [:ups_license_number, :ups_shipper_number, :ups_user, :ups_password]
       # @required +=  [:phone, :email, :company, :address, :city, :state, :zip]
       # @required += [:sender_phone, :sender_email, :sender_company, :sender_address, :sender_city, :sender_state, :sender_zip ]
        packages = Array(packages)
        pickup_date = options[:pickup_date] ? Date.parse(options[:pickup_date]).strftime("%Y%m%d") : Time.now.strftime("%Y%m%d")

        xml_request = XmlNode.new('ShipmentConfirmRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'ShipConfirm')
            request << XmlNode.new('RequestOption', "nonvalidate")
            request << XmlNode.new('TransactionReference') do |ref|
              # request << XmlNode.new('XpciVersion', '1.0001')
              ref << XmlNode.new('CustomerContext', "#{destination.city}, #{destination.state} #{destination.zip}")
            end
          end

          root_node << XmlNode.new('Shipment') do |shipment|
            unless options[:return_service_code].nil?
              shipment << XmlNode.new('ReturnService') do |rs_node|
                rs_node << XmlNode.new('Code', options[:return_service_code])
              end
            end
            shipment << XmlNode.new('Description', options[:description])
            
            shipment << build_location_node('Shipper', (options[:shipper] || origin), options)
            shipment << build_location_node('ShipTo', destination, options)
            if options[:shipper] and options[:shipper] != origin
              shipment << build_location_node('ShipFrom', origin, options)
            end


          
            shipment << XmlNode.new('PaymentInformation') do |payment|
              pay_type = PAYMENT_TYPES[options[:pay_type]] || 'Prepaid'

              if pay_type == 'Prepaid'
                payment << XmlNode.new('Prepaid') do |prepaid|
                  prepaid << XmlNode.new('BillShipper') do |bill_shipper|
                    if options[:origin_account]
                      bill_shipper << XmlNode.new('AccountNumber', options[:origin_account])
                    else
                      puts "We need an origin account!"
                    end
                  end
                end
              elsif pay_type == 'BillThirdParty'
                payment << XmlNode.new('BillThirdParty') do |bt|
                  bt << XmlNode.new('BillThirdPartyShipper') do |bt_shipper|
                    bt_shipper << XmlNode.new('AccountNumber', options[:billing_account])
                    bt_shipper << XmlNode.new('ThirdParty') do |third_party|
                      third_party << XmlNode.new('Address') do |tp_address|
                        tp_address << XmlNode.new('PostalCode', options[:billing_zip])
                        tp_address << XmlNode.new('CountryCode', options[:billing_country])
                      end
                    end
                  end
                end
              elsif pay_type == 'FreightCollect'
                payment << XmlNode.new('FreightCollect') do |fc|
                  fc << XmlNode.new('BillReceiver') do |bill_receiver|
                    bill_receiver << XmlNode.new('AccountNumber', options[:billing_account])
                  end
                end
              else
                # raise ShippingError, "Valid pay_types are 'prepaid', 'bill_third_party', or 'freight_collect'."
                puts "OH Noes! We need to figure out how to raise an error!"
              end
            end # end payment node
          
            shipment << XmlNode.new('Service') do |service|
              service << XmlNode.new('Code', DEFAULT_SERVICES.invert[options[:service_type]] || '03')  # defaults to ground
            end
          
            packages.each do |package|
              imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))
            
              shipment << XmlNode.new("Package") do |package_node|
              
                # not implemented:  * Shipment/Package/PackagingType element
                #                   * Shipment/Package/Description element
              
                package_node << XmlNode.new("PackagingType") do |packaging_type|
                  packaging_type << XmlNode.new("Code", '02')
                end
              
                package_node << XmlNode.new("Dimensions") do |dimensions|
                  dimensions << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'IN' : 'CM')
                  end
                  [:length,:width,:height].each do |axis|
                    value = ((imperial ? package.inches(axis) : package.cm(axis)).to_f*1000).round/1000.0 # 3 decimals
                    dimensions << XmlNode.new(axis.to_s.capitalize, [value,0.1].max)
                  end
                end
            
                package_node << XmlNode.new("PackageWeight") do |package_weight|
                  package_weight << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'LBS' : 'KGS')
                  end
                
                  value = ((imperial ? package.lbs : package.kgs).to_f*1000).round/1000.0 # 3 decimals
                  package_weight << XmlNode.new("Weight", [value,0.1].max)
                end
            
                # not implemented:  * Shipment/Package/LargePackageIndicator element
                #                   * Shipment/Package/ReferenceNumber element
                #                   * Shipment/Package/PackageServiceOptions element
                #                   * Shipment/Package/AdditionalHandling element  
              end
              # TODO: we'll need insurance value and the like to be validated
            end # end Packages
          end # end Shipment
          root_node << XmlNode.new('LabelSpecification') do |label_spec|
            image_type = options[:image_type] || 'GIF' # default to GIF

            label_spec << XmlNode.new('LabelPrintMethod') do |lp_meth|
              lp_meth << XmlNode.new('Code', image_type)
            end
            if image_type == 'GIF'
              label_spec << XmlNode.new('HTTPUserAgent', 'Mozilla/5.0')
              label_spec << XmlNode.new('LabelImageFormat') do |label_format|
                label_format << XmlNode.new('Code', 'GIF')
              end
            elsif image_type == 'EPL'
              label_spec << XmlNode.new('LabelStockSize') do |lstock_size|
                lstock_size << XmlNode.new('Height', '4')
                lstock_size << XmlNode.new('Width', '6')
              end
            else
              # raise ShippingError, "Valid image_types are 'EPL' or 'GIF'."
              puts "Oh Noes! We don't know what to do with errors!"
            end
          end # end Label Spec
          
        end # end ShipmentConfirmRequest
        
        access_request = build_access_request
        label_request = xml_request.to_s
        req = access_request + label_request
        puts req.to_s
        response = commit(:label, save_request(req), (options[:test] || true))
        
        # xml = REXML::Document.new(response)
        #     success = response_success?(xml)
        #     message = response_message(xml)
        #     
        #     if success
        # 
        # 
        #      # get ConfirmResponse
        #      get_response @ups_url + @ups_tool
        #      begin
        #        shipment_digest = REXML::XPath.first(@response, '//ShipmentConfirmResponse/ShipmentDigest').text
        #      rescue
        #        raise ShippingError, get_error
        #      end
        # 
        #      # make AcceptRequest and get AcceptResponse
        #      @ups_tool = '/ShipAccept'
        # 
        #      b = request_access
        #      b.instruct!
        # 
        #      b.ShipmentAcceptRequest { |b|
        #        b.Request { |b|
        #          b.RequestAction "ShipAccept"
        #          b.TransactionReference { |b|
        #            b.CustomerContext "#{@city}, #{state} #{@zip}"
        #            b.XpciVersion API_VERSION
        #          }
        #        }
        #        b.ShipmentDigest shipment_digest
        #      }
        # 
        #      # get AcceptResponse
        #      get_response @ups_url + @ups_tool
        # 
        #      begin  
        #        response = Hash.new       
        #        if @single_package
        #          response[:tracking_number] = REXML::XPath.first(@response, "//ShipmentAcceptResponse/ShipmentResults/PackageResults/TrackingNumber").text
        #          response[:encoded_image] = REXML::XPath.first(@response, "//ShipmentAcceptResponse/ShipmentResults/PackageResults/LabelImage/GraphicImage").text
        #          extension = REXML::XPath.first(@response, "//ShipmentAcceptResponse/ShipmentResults/PackageResults/LabelImage/LabelImageFormat/Code").text
        #          response[:image] = Tempfile.new(["shipping_label", '.' + extension.downcase])
        #          response[:image].write Base64.decode64( response[:encoded_image] )
        #          response[:image].rewind
        # 
        #          # if this package has a high insured value
        #          high_value_report = REXML::XPath.first(@response, "//ShipmentAcceptResponse/ShipmentResults/ControlLogReceipt/GraphicImage")
        #          if high_value_report
        #            extension = REXML::XPath.first(@response, "//ShipmentAcceptResponse/ShipmentResults/ControlLogReceipt/ImageFormat/Code").text
        #            response[:encoded_high_value_report] = high_value_report.text
        #            response[:high_value_report] = Tempfile.new(["high_value_report", '.' + extension.downcase])
        #            response[:high_value_report].write Base64.decode64( response[:encoded_high_value_report] )
        #            response[:high_value_report].rewind
        #          end
        #        else
        #          response[:packages] = []
        #          REXML::XPath.each(@response, "//ShipmentAcceptResponse/ShipmentResults/PackageResults") do |package_element|
        #            response[:packages] << {}
        #            response[:packages].last[:tracking_number] = REXML::XPath.first(package_element, "TrackingNumber").text
        #            response[:packages].last[:encoded_label] = REXML::XPath.first(package_element, "LabelImage/GraphicImage").text
        #            extension = response[:packages].last[:encoded_label] = REXML::XPath.first(package_element, "LabelImage/LabelImageFormat/Code").text
        #            response[:packages].last[:label_file] = Tempfile.new(["shipping_label_#{Time.now}_#{Time.now.usec}", '.' + extension.downcase])
        #            response[:packages].last[:label_file].write Base64.decode64( response[:packages].last[:encoded_label] )
        #            response[:packages].last[:label_file].rewind
        # 
        #            # if this package has a high insured value
        #            high_value_report = REXML::XPath.first(package_element, "//ShipmentAcceptResponse/ShipmentResults/ControlLogReceipt/GraphicImage")
        #            if high_value_report
        #              extension = REXML::XPath.first(package_element, "//ShipmentAcceptResponse/ShipmentResults/ControlLogReceipt/ImageFormat/Code").text
        #              response[:packages].last[:encoded_high_value_report] = high_value_report.text
        #              response[:packages].last[:high_value_report] = Tempfile.new(["high_value_report", '.' + extension.downcase])
        #              response[:packages].last[:high_value_report].write Base64.decode64( response[:packages].last[:encoded_high_value_report] )
        #              response[:packages].last[:high_value_report].rewind
        #            end
        #          end
        #        end
        #      rescue
        #        raise ShippingError, get_error
        #      end
        # 
        #      # allows for things like fedex.label.url
        #      def response.method_missing(name, *args)
        #        has_key?(name) ? self[name] : super
        #      end
        # 
        #      # don't allow people to edit the response
        #      response.freeze
      end      
            
      def build_location_node(name,location,options={})
        location_node = XmlNode.new(name) do |location_node|
          location_node << XmlNode.new('PhoneNumber', location.phone.gsub(/[^\d]/,'')) unless location.phone.blank?
          location_node << XmlNode.new('FaxNumber', location.fax.gsub(/[^\d]/,'')) unless location.fax.blank?
          
          # Name
          if name == 'Shipper'
            location_node << XmlNode.new('Name', location.name)
          end
          
          location_node << XmlNode.new('CompanyName', location.company_name) unless location.company_name.blank?
          location_node << XmlNode.new('AttentionName', location.attention_name) unless location.attention_name.blank?
          location_node << XmlNode.new('TaxIdentificationNumber', location.tax_id) unless location.tax_id.blank?
          
          if name == 'Shipper' and (origin_account = @options[:origin_account] || options[:origin_account])
            location_node << XmlNode.new('ShipperNumber', origin_account)
          elsif name == 'ShipTo' and (destination_account = @options[:destination_account] || options[:destination_account])
            location_node << XmlNode.new('ShipperAssignedIdentificationNumber', destination_account)
          end
          
          location_node << XmlNode.new('Address') do |address|
            address << XmlNode.new("AddressLine1", location.address1) unless location.address1.blank?
            address << XmlNode.new("AddressLine2", location.address2) unless location.address2.blank?
            address << XmlNode.new("AddressLine3", location.address3) unless location.address3.blank?
            address << XmlNode.new("City", location.city) unless location.city.blank?
            address << XmlNode.new("StateProvinceCode", location.province) unless location.province.blank?
              # StateProvinceCode required for negotiated rates but not otherwise, for some reason
            address << XmlNode.new("PostalCode", location.postal_code) unless location.postal_code.blank?
            address << XmlNode.new("CountryCode", location.country_code(:alpha2)) unless location.country_code(:alpha2).blank?
            address << XmlNode.new("ResidentialAddressIndicator", true) unless location.commercial? # the default should be that UPS returns residential rates for destinations that it doesn't know about
            # not implemented: Shipment/(Shipper|ShipTo|ShipFrom)/Address/ResidentialAddressIndicator element
          end
        end
      end
      
      def parse_rate_response(origin, destination, packages, response, options={})
        rates = []
        
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        
        if success
          rate_estimates = []
          
          xml.elements.each('/*/RatedShipment') do |rated_shipment|
            service_code = rated_shipment.get_text('Service/Code').to_s
            days_to_delivery = rated_shipment.get_text('GuaranteedDaysToDelivery').to_s.to_i
            days_to_delivery = nil if days_to_delivery == 0

            rate_estimates << RateEstimate.new(origin, destination, @@name,
                                service_name_for(origin, service_code),
                                :total_price => rated_shipment.get_text('TotalCharges/MonetaryValue').to_s.to_f,
                                :currency => rated_shipment.get_text('TotalCharges/CurrencyCode').to_s,
                                :service_code => service_code,
                                :packages => packages,
                                :delivery_range => [timestamp_from_business_day(days_to_delivery)])
          end
        end
        RateResponse.new(success, message, Hash.from_xml(response).values.first, :rates => rate_estimates, :xml => response, :request => last_request)
      end
      
      def parse_transit_time_response(origin, destination, packages, response, options={})
        puts response.inspect
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        
        if success
          times = {}
          
          xml.elements.each('/*/ServiceSummary') do |timed_shipment|
            service_code = timed_shipment.get_text('Service/Code').to_s
            times[service_code] = {
              :service_name => service_name_for(origin, service_code),
              # :service => ServiceTimes.index(index),
              :days => timed_shipment.get_text("EstimatedArrival/BusinessTransitDays").to_i,
              :date => timed_shipment.get_text("EstimatedArrival/Date").to_date,
              :time => timed_shipment.get_text("EstimatedArrival/Time"),
              }

            # rate_estimates << RateEstimate.new(origin, destination, @@name,
            #                     service_name_for(origin, service_code),
            #                     :total_price => rated_shipment.get_text('TotalCharges/MonetaryValue').to_s.to_f,
            #                     :currency => rated_shipment.get_text('TotalCharges/CurrencyCode').to_s,
            #                     :service_code => service_code,
            #                     :packages => packages,
            #                     :delivery_range => [timestamp_from_business_day(days_to_delivery)])
          end
        end
        # RateResponse.new(success, message, Hash.from_xml(response).values.first, :rates => rate_estimates, :xml => response, :request => last_request)
        return times
      end
      
      def parse_tracking_response(response, options={})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        
        if success
          tracking_number, origin, destination, status_code, status_description = nil
          delivered, exception = false
          exception_event = nil
          shipment_events = []
          status = {}
          scheduled_delivery_date = nil

          first_shipment = xml.elements['/*/Shipment']
          first_package = first_shipment.elements['Package']
          tracking_number = first_shipment.get_text('ShipmentIdentificationNumber | Package/TrackingNumber').to_s
          
          # Build status hash
          status_node = first_package.elements['Activity/Status/StatusType']
          status_code = status_node.get_text('Code').to_s
          status_description = status_node.get_text('Description').to_s
          status = TRACKING_STATUS_CODES[status_code]

          if status_description =~ /out.*delivery/i
            status = :out_for_delivery
          end

          origin, destination = %w{Shipper ShipTo}.map do |location|
            location_from_address_node(first_shipment.elements["#{location}/Address"])
          end

          # Get scheduled delivery date
          unless status == :delivered
            scheduled_delivery_date = parse_ups_datetime({
              :date => first_shipment.get_text('ScheduledDeliveryDate'),
              :time => nil
              })
          end

          activities = first_package.get_elements('Activity')
          unless activities.empty?
            shipment_events = activities.map do |activity|
              description = activity.get_text('Status/StatusType/Description').to_s
              zoneless_time = if (time = activity.get_text('Time')) &&
                                 (date = activity.get_text('Date'))
                time, date = time.to_s, date.to_s
                hour, minute, second = time.scan(/\d{2}/)
                year, month, day = date[0..3], date[4..5], date[6..7]
                Time.utc(year, month, day, hour, minute, second)
              end
              location = location_from_address_node(activity.elements['ActivityLocation/Address'])
              ShipmentEvent.new(description, zoneless_time, location)
            end
            
            shipment_events = shipment_events.sort_by(&:time)
            
            # UPS will sometimes archive a shipment, stripping all shipment activity except for the delivery 
            # event (see test/fixtures/xml/delivered_shipment_without_events_tracking_response.xml for an example).
            # This adds an origin event to the shipment activity in such cases.
            if origin && !(shipment_events.count == 1 && status == :delivered)
              first_event = shipment_events[0]
              same_country = origin.country_code(:alpha2) == first_event.location.country_code(:alpha2)
              same_or_blank_city = first_event.location.city.blank? or first_event.location.city == origin.city
              origin_event = ShipmentEvent.new(first_event.name, first_event.time, origin)
              if same_country and same_or_blank_city
                shipment_events[0] = origin_event
              else
                shipment_events.unshift(origin_event)
              end
            end

            # Has the shipment been delivered?
            if status == :delivered
              if !destination
                destination = shipment_events[-1].location
              end
              shipment_events[-1] = ShipmentEvent.new(shipment_events.last.name, shipment_events.last.time, destination)
            end
          end
          
        end
        TrackingResponse.new(success, message, Hash.from_xml(response).values.first,
          :carrier => @@name,
          :xml => response,
          :request => last_request,
          :status => status,
          :status_code => status_code,
          :status_description => status_description,
          :scheduled_delivery_date => scheduled_delivery_date,
          :shipment_events => shipment_events,
          :delivered => delivered,
          :exception => exception,
          :exception_event => exception_event,
          :origin => origin,
          :destination => destination,
          :tracking_number => tracking_number)
      end
      
      def location_from_address_node(address)
        return nil unless address
        Location.new(
                :country =>     node_text_or_nil(address.elements['CountryCode']),
                :postal_code => node_text_or_nil(address.elements['PostalCode']),
                :province =>    node_text_or_nil(address.elements['StateProvinceCode']),
                :city =>        node_text_or_nil(address.elements['City']),
                :address1 =>    node_text_or_nil(address.elements['AddressLine1']),
                :address2 =>    node_text_or_nil(address.elements['AddressLine2']),
                :address3 =>    node_text_or_nil(address.elements['AddressLine3'])
              )
      end
      
      def parse_ups_datetime(options = {})
        time, date = options[:time].to_s, options[:date].to_s
        if time.nil?
          hour, minute, second = 0
        else
          hour, minute, second = time.scan(/\d{2}/)
        end
        year, month, day = date[0..3], date[4..5], date[6..7]

        Time.utc(year, month, day, hour, minute, second)
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
      
      
      def service_name_for(origin, code)
        origin = origin.country_code(:alpha2)
        
        name = case origin
        when "CA" then CANADA_ORIGIN_SERVICES[code]
        when "MX" then MEXICO_ORIGIN_SERVICES[code]
        when *EU_COUNTRY_CODES then EU_ORIGIN_SERVICES[code]
        end
        
        name ||= OTHER_NON_US_ORIGIN_SERVICES[code] unless name == 'US'
        name ||= DEFAULT_SERVICES[code]
      end
      
    end
  end
end
