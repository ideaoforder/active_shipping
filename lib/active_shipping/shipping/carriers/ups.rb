# -*- encoding: utf-8 -*-

module ActiveMerchant
  module Shipping
    class UPS < Carrier
      require 'tempfile'
      self.retry_safe = true
      
      cattr_accessor :default_options
      cattr_reader :name
      @@name = "UPS"
      
      TEST_URL = 'https://wwwcie.ups.com'
      LIVE_URL = 'https://onlinetools.ups.com'
      
      RESOURCES = {
        :rates => 'ups.app/xml/Rate',
        :track => 'ups.app/xml/Track',
        :label => 'ups.app/xml/ShipConfirm',
        :void  => 'ups.app/xml/Void',
        :accept => 'ups.app/xml/ShipAccept'
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
        "86" => "UPS Today Express Saver",
        "72" => "UPS Expedited Mail Innovations",
        "73" => "UPS Priority Mail Innovations",
        "74" => "UPS Economy Mail Innovations"
      }
      
      CANADA_ORIGIN_SERVICES = {
        "01" => "UPS Express",
        "02" => "UPS Expedited",
        "14" => "UPS Express Early A.M.",
        "73" => "UPS Priority Mail Innovations",
        "74" => "UPS Economy Mail Innovations"
      }
      
      MEXICO_ORIGIN_SERVICES = {
        "07" => "UPS Express",
        "08" => "UPS Expedited",
        "54" => "UPS Express Plus",
        "73" => "UPS Priority Mail Innovations",
        "74" => "UPS Economy Mail Innovations"
      }
      
      EU_ORIGIN_SERVICES = {
        "07" => "UPS Express",
        "08" => "UPS Expedited",
        "73" => "UPS Priority Mail Innovations",
        "74" => "UPS Economy Mail Innovations"
      }
      
      OTHER_NON_US_ORIGIN_SERVICES = {
        "07" => "UPS Express",
        "73" => "UPS Priority Mail Innovations",
        "74" => "UPS Economy Mail Innovations"
      }

      MAIL_INNOVATIONS_SERVICES = {
        "72" => "UPS Expedited Mail Innovations",
        "73" => "UPS Priority Mail Innovations",
        "74" => "UPS Economy Mail Innovations"        
      }

      WORLDWIDE_SERVICES = {
        '08' => 'UPS Worldwide Expedited', 
        '07' => 'UPS Worldwide Express',  
        '54' => 'UPS Worldwide Express Plus'
      }

      TRACKING_STATUS_CODES = HashWithIndifferentAccess.new({
        'I' => :in_transit,
        'D' => :delivered,
        'X' => :exception,
        'P' => :pickup,
        'M' => :manifest_pickup
      })

      UPS_PACKAGING_TYPES = {
        '01' => 'UPS Letter', 
        '02' => 'Customer Supplied Package', 
        '03' => 'Tube', 
        '04' => 'PAK', 
        '21' => 'UPS Express Box', 
        '24' => 'UPS 25KG Box', 
        '25' => 'UPS 10KG Box', 
        '30' => 'Pallet', 
        '2a' => 'Small Express Box', 
        '2b' => 'Medium Express Box', 
        '2c' => 'Large Express Box', 
        '56' => 'Flats', 
        '57' => 'Parcels', 
        '58' => 'BPM'
      }

      MI_PACKAGING_TYPES = {
        '59' => 'First Class', 
        '60' => 'Priority', 
        '61' => 'Machinables', 
        '62' => 'Irregulars', 
        '63' => 'Parcel Post', 
        '64' => 'BPM Parcel', 
        '65' => 'Media Mail', 
        '66' => 'BMP Flat', 
        '67' => 'Standard Flat'
      }

      PACKAGING_TYPES = UPS_PACKAGING_TYPES.merge(MI_PACKAGING_TYPES)    

      UOM = {
        "BA"=>"Barrel", 
        "BE"=>"Bundle", 
        "BG"=>"Bag", 
        "BH"=>"Bunch", 
        "BOX"=>"Box", 
        "BT"=>"Bolt", 
        "BU"=>"Butt", 
        "CI"=>"Canister", 
        "CM"=>"Centimeter", 
        "CON"=>"Container ", 
        "CR"=>"Crate", 
        "CS"=>"Case", 
        "CT"=>"Carton", 
        "CY"=>"Cylinder", 
        "DOZ"=>"Dozen", 
        "EA"=>"Each", 
        "EN"=>"Envelope", 
        "FT"=>"Feet", 
        "KG"=>"Kilogram", 
        "KGS"=>"Kilograms", 
        "LB"=>"Pound", 
        "LBS"=>"Pounds", 
        "L"=>"Liter", 
        "M"=>"Meter", 
        "NMB"=>"Number", 
        "PA"=>"Packet", 
        "PAL"=>"Pallet", 
        "PC"=>"Piece", 
        "PCS"=>"Pieces", 
        "PF"=>"Proof Liters", 
        "PKG"=>"Package ", 
        "PR"=>"Pair", 
        "PRS"=>"Pairs", 
        "RL"=>"Roll", 
        "SET"=>"Set", 
        "SME"=>"Square Meters", 
        "SYD"=>"Square Yards", 
        "TU"=>"Tube", "
        YD"=>"Yard", 
        "OTH"=>"Other"
      }

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
      
      def get_label(origin, destination, packages, options={})
        origin, destination = upsified_location(origin), upsified_location(destination)
        options = @options.merge(options)
        packages = Array(packages)
        access_request = build_access_request
        
        label_request = build_label_request(origin, destination, packages, options)
        req = access_request + label_request
      puts "LABEL REQUEST: " + req
        response = commit(:label, save_request(req), (options[:test] || false))
      puts "LABEL RESPONSE: " + response
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        if success
          begin
            shipment_digest = xml.elements['/*/ShipmentDigest'].text
          rescue => e
            raise ArgumentError, e.inspect
          end
        else
          raise ArgumentError, message
        end

        accept_request = build_accept_request(shipment_digest)
        req = access_request + accept_request
      puts "ACCEPT REQUEST: " + req
        response = commit(:accept, save_request(req), (options[:test] || false))
      puts "ACCEPT RESPONSE: " + response
        parse_label_response(origin, destination, packages, response, options)
      end

      def void_label(shipping_id, tracking_numbers=[], options={})
        access_request = build_access_request
        void_request = build_void_request(shipping_id, tracking_numbers)
        # NOTE: For some reason, this request requires the xml version
        req = '<?xml version="1.0"?>' + access_request + '<?xml version="1.0"?>' + void_request
        response = commit(:void, save_request(req), (options[:test] || false))
        parse_void_response(response, tracking_numbers)
      end
      
      protected
      
      def upsified_location(location)
        if location.country_code == 'US' && US_TERRITORIES_TREATED_AS_COUNTRIES.include?(location.state)
          atts = {:country => location.state}
          [:zip, :city, :address1, :address2, :address3, :phone, :fax, :address_type].each do |att|
            atts[att] = location.send(att)
          end
          Location.new(atts)
        elsif !%w[CA US].include? location.country_code(:alpha2)
          atts = {}
          keys = location.to_hash.keys
          keys.delete(:province)
          keys.each do |att|
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
        imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))
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

                if options[:adult_signature_required]
                  options[:delivery_confirmation] = '1'
                elsif options[:signature_required]
                  options[:delivery_confirmation] = '2'
                elsif options[:delivery_confirmation]
                  options[:delivery_confirmation] = '3'
                else
                  options[:delivery_confirmation] = false
                end

                if options[:insurance] or options[:delivery_confirmation]
                  package_node << XmlNode.new("PackageServiceOptions") do |pso|
                    if options[:insurance] and !package.value.blank? and package.value > 0.0
                      pso << XmlNode.new("InsuredValue") do |insured_value|
                        insured_value << XmlNode.new("CurrencyCode", package.currency || 'USD')
                        insured_value << XmlNode.new("MonetaryValue", package.value)
                      end
                    end
                    if options[:delivery_confirmation]
                      pso << XmlNode.new("DeliveryConfirmation") do |dc|
                        dc << XmlNode.new("DCISType", options[:delivery_confirmation])
                      end
                    end
                  end
                end  
              
                # not implemented:  * Shipment/Package/LargePackageIndicator element
                #                   * Shipment/Package/ReferenceNumber element
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
            
      # See Ship-WW-XML.pdf for API info
       # @image_type = [GIF|EPL] 
      def build_label_request(origin, destination, packages, options={})
        # @required = :origin_account, 
        # @destination +=  [:phone, :email, :company, :address, :city, :state, :zip]
        # @shipper += [:sender_phone, :sender_email, :sender_company, :sender_address, :sender_city, :sender_state, :sender_zip ]
        missing_required = Array.new
        errors = Array.new

        packages = Array(packages)
        mail_innovations = MAIL_INNOVATIONS_SERVICES.values.include? options[:service_type]
        domestic = (origin.country_code(:alpha2) == 'US' and destination.country_code(:alpha2) == 'US') ? true : false
        imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))

        pickup_date = options[:pickup_date] ? Date.parse(options[:pickup_date]).strftime("%Y%m%d") : Time.now.strftime("%Y%m%d")
        if options[:adult_signature_required]
          options[:delivery_confirmation] = '1'
        elsif options[:signature_required]
          options[:delivery_confirmation] = '2'
        elsif options[:delivery_confirmation]
          options[:delivery_confirmation] = '3'
        else
          options[:delivery_confirmation] = false
        end

        xml_request = XmlNode.new('ShipmentConfirmRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'ShipConfirm')
            request << XmlNode.new('RequestOption', "nonvalidate")
            request << XmlNode.new('TransactionReference') do |ref|
              # request << XmlNode.new('XpciVersion', '1.0001')
              customer_context = options[:reference_number] || destination.zip
              ref << XmlNode.new('CustomerContext', customer_context)
            end
          end

          root_node << XmlNode.new('Shipment') do |shipment|
            unless options[:return_service_code].nil?
              shipment << XmlNode.new('ReturnService') do |rs_node|
                rs_node << XmlNode.new('Code', options[:return_service_code])
              end
            end
            shipment << XmlNode.new('Description', options[:description])
            
            shipment << build_location_node('ShipFrom', origin, options)

            for field in %w[address1 company_name city zip country]
              missing_required << "ShipTo #{field}" if destination.send(field).blank?
            end

            # State/Province is only required for US/Canada
            if !%w[GB US].include? destination.country_code(:alpha2)
              missing_required << "ShipTo #{field}" if destination.send(field).blank?
            end
            shipment << build_location_node('ShipTo', destination, options)

            if options[:shipper] and options[:shipper] != origin
              shipper = options[:shipper]
            else
              shipper = origin
            end
            # TODO: validate alias methods too
            for field in %w[phone email name company_name address1 city state zip country]
              missing_required << "Shipper #{field}" if shipper.send(field).blank?
            end
            shipment << build_location_node('Shipper', shipper, options)

            # MAIL INNOVATIONS
            if mail_innovations
              shipment << XmlNode.new('USPSEndorsement', domestic ? '1' : '5')
              if !domestic
                errors << "Only one package may be shipped with Mail Innovations" if packages.length > 1
                package = packages.first
                shipment << XmlNode.new('MILabelCN22Indicator', '1')
                shipment << XmlNode.new('ShipmentServiceOptions') do |sso|
                  sso << XmlNode.new('InternationalForms') do |intl_forms|

                    # Products Form
                    customs_info = options[:customs_info]
                    if customs_info and customs_info.customs_items and customs_info.customs_items.length > 0
                      customs_quantity = 0
                      for item in customs_info.customs_items
                        customs_quantity += item.quantity
                        intl_forms << XmlNode.new('Product') do |product|
                          product << XmlNode.new("Description", item.description[0..34])
                          product << XmlNode.new('Unit') do |unit|
                            unit << XmlNode.new("Number", item.quantity)
                            unit << XmlNode.new("Value", item.value)
                            unit << XmlNode.new("UnitOfMeasurement") do |uom|
                              uom << XmlNode.new("Code", "PCS") # TODO: This is hardcoded to 'PCS' for now
                              # /Description
                            end
                          end
                          # /CommodityCode
                          # /PartNumber
                          product << XmlNode.new("OriginCountryCode", origin.country_code(:alpha2))
                          # /JointProductionIndicator
                        end # end product
                      end
                    end # end customs check

                    # Customs Form
                    intl_forms << XmlNode.new('FormType', '09') # CN22
                    intl_forms << XmlNode.new('CN22Form') do |cn22|
                      # 6 = 4X6 or 1 = 8.5X11
                      cn22 << XmlNode.new('LabelSize', options[:label_size] || '6')
                      cn22 << XmlNode.new('PrintsPerPage', '1') # only option at the moment
                      # pdf,png,gif,zpl,star,epl2 and spl
                      cn22 << XmlNode.new('LabelPrintType', options[:image_type])
                      # 1 = GIFT 2 = DOCUMENTS 3 = COMMERCIAL SAMPLE, 4 = OTHER
                      # NOTE: GIFT and OTHER are currently the only supported options
                      cn22 << XmlNode.new('CN22Type', options[:gift] ? '1' : '4')
                      cn22 << XmlNode.new('CN22OtherDescription', "MERCHANDISE") unless options[:gift]
                      cn22 << XmlNode.new('FoldHereText', options[:fold_here_text]) if options[:fold_here_text]
                      cn22 << XmlNode.new('CN22Content') do |cn22_content|
                        # TODO!!!
                        quantity = 
                        cn22_content << XmlNode.new('CN22ContentQuantity', customs_quantity ? customs_quantity : '1')
                        cn22_content << XmlNode.new('CN22ContentDescription', customs_info ? customs_info.description : 'Merchandise')
                        cn22_content << XmlNode.new("CN22ContentWeight") do |cn22_weight|
                          cn22_weight << XmlNode.new("UnitOfMeasurement") do |units|
                            units << XmlNode.new("Code", imperial ? 'lbs' : 'ozs')
                            # /Description
                          end
                          value = ((imperial ? package.lbs : package.kgs).to_f*100).round/100.0 # 2 decimals
                          cn22_weight << XmlNode.new("Weight", [value,0.1].max)
                        end
                        cn22_content << XmlNode.new('CN22ContentTotalValue', package.value)
                        cn22_content << XmlNode.new('CN22ContentCurrencyCode', 'USD') # only supports USD
                        cn22_content << XmlNode.new('CN22ContentCountryOfOrigin', origin.country_code(:alpha2))
                        # /CN22ContentTariffNumber
                      end # end CN22Content
                    end # end CN22
                  end
                end
              end # End INTL shipment
              shipment << XmlNode.new('SubClassification', options[:irregular] ? 'IR' : 'MA')
              shipment << XmlNode.new('CostCenter', options[:cost_center] || "costcenter123")
              unless destination.province == 'Puerto Rico' or destination.country_code == 'PR'
                shipment << XmlNode.new('PackageID', options[:reference_number])
              end
              # /ShipmentConfirmRequest/Shipment/IrregularIndicator
            end
            # END MAIL INNOVATIONS

            shipment << XmlNode.new('PaymentInformation') do |payment|
              # Mail Innovations can only be prepaid
              pay_type = (mail_innovations or !options[:pay_type]) ? 'Prepaid' : PAYMENT_TYPES[options[:pay_type]]
              if pay_type == 'Prepaid'
                payment << XmlNode.new('Prepaid') do |prepaid|
                  prepaid << XmlNode.new('BillShipper') do |bill_shipper|
                    if options[:origin_account] and !options[:origin_account].blank?
                      bill_shipper << XmlNode.new('AccountNumber', options[:origin_account])
                    else
                      missing_required << "Shipper number (origin_account)"
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
                        country = options[:billing_country].nil? ? nil : ActiveMerchant::Country.find(options[:billing_country])
                        if !country.blank?
                          country_code = country.code(:alpha2).value
                        else
                          country_code = options[:billing_country]
                        end
                        tp_address << XmlNode.new('CountryCode', country_code)
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
                errors << "Valid pay_types are 'prepaid', 'bill_third_party', or 'freight_collect'."
              end
            end # end payment node
          
            shipment << XmlNode.new('Service') do |service|
              service << XmlNode.new('Code', DEFAULT_SERVICES.invert[options[:service_type]] || '03')  # defaults to ground
            end

            if origin.country_code == 'US' and (destination.country_code == 'CA' or destination.province == 'Puerto Rico' or destination.country_code == 'PR' )
              shipment << XmlNode.new('InvoiceLineTotal') do |ilt|
                ival = options[:value] ? options[:value].to_f.ceil.to_i : 1
                ilt << XmlNode.new("CurrencyCode", options[:currency] || 'USD')
                ilt << XmlNode.new("MonetaryValue", [ival, 1].max.to_s)
              end
            end
          
            packages.each do |package|
              imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))
            
              shipment << XmlNode.new("Package") do |package_node|
              
                # not implemented:  * Shipment/Package/Description element
              
                package_node << XmlNode.new("PackagingType") do |packaging_type|
                  if mail_innovations 
                    if domestic
                      default_packaging = "Parcel Post" 
                    else
                      default_packaging = "Parcels"
                    end
                  else
                    default_packaging = "Customer Supplied Package"
                  end
                  packaging_type << XmlNode.new("Code", PACKAGING_TYPES.invert[package.packaging_type || default_packaging])
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

                if !options[:reference_number].blank? and !(MAIL_INNOVATIONS_SERVICES.values + WORLDWIDE_SERVICES.values).include?(options[:service_type]) and (destination.province != 'Puerto Rico' and destination.country_code != 'PR')
                  package_node << XmlNode.new("ReferenceNumber") do |ref_num|
                    ref_num << XmlNode.new("Code", '02')
                    ref_num << XmlNode.new("Value", options[:reference_number])
                  end
                end

                # MI doesn't allow these options
                if (options[:insurance] or options[:delivery_confirmation]) and !mail_innovations
                  package_node << XmlNode.new("PackageServiceOptions") do |pso|
                    if options[:insurance] and !package.value.blank? and package.value > 0.0
                      pso << XmlNode.new("InsuredValue") do |insured_value|
                        insured_value << XmlNode.new("CurrencyCode", package.currency || 'USD')
                        insured_value << XmlNode.new("MonetaryValue", package.value)
                      end
                    end
                    if options[:delivery_confirmation]
                      pso << XmlNode.new("DeliveryConfirmation") do |dc|
                        dc << XmlNode.new("DCISType", options[:delivery_confirmation])
                      end
                    end
                  end
                end  
                # not implemented:  * Shipment/Package/LargePackageIndicator element
                #                   * Shipment/Package/AdditionalHandling element  
              end
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
              errors << "Valid image_types are 'EPL' or 'GIF'."
            end
          end # end Label Spec
          
        end # end ShipmentConfirmRequest

        # There are a lot of required fields for the label request to work
        # We collect them all in one error, so it doesn't take folks 20 tries to construct a working request
        errors << "UPS labels require: #{missing_required.join(', ')}" if missing_required.length > 0

        # Now we spit out all of the errors; 
        # We don't even want to make the request if we know it won't go through
        raise ArgumentError.new(errors.join('; ')) if errors.length > 0

        xml_request.to_s
      end      

      def build_accept_request(shipment_digest, description='Shipping Label')
        xml_request = XmlNode.new('ShipmentAcceptRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'ShipAccept')
            request << XmlNode.new('TransactionReference') do |ref|
              ref << XmlNode.new('CustomerContext', description)
            end
            root_node << XmlNode.new('ShipmentDigest', shipment_digest)
          end
        end
        xml_request.to_s
      end

      # This voids a shipment
      # if multiple tracking numbers are passed in, it will attempt to void them all in a single call
      # if ANY of them fails, we return false and hand over the array of results
      def build_void_request(shipping_id, tracking_numbers = [])
        xml_request = XmlNode.new('VoidShipmentRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Void')
            request << XmlNode.new('TransactionReference') do |ref|
              ref << XmlNode.new('CustomerContext', "Void Label")
            end
          end
          if tracking_numbers.length > 1
            root_node << XmlNode.new('ExpandedVoidShipment') do |evs|
              evs << XmlNode.new('RequestAction', 'Void')
              evs << XmlNode.new('ShipmentIdentificationNumber', shipping_id)
              for num in tracking_numbers
                evs << XmlNode.new('TrackingNumber', num)
              end
            end
          else
            root_node << XmlNode.new('ShipmentIdentificationNumber', shipping_id)
          end
        end
        xml_request.to_s
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

          if options[:mail_innovations]
            error = false
            domestic = (origin.country_code(:alpha2) == 'US' and destination.country_code(:alpha2) == 'US') ? true : false
            if domestic
              service_code = "72"
              # listed_rates = MI_EXPEDITED_RATES
              range = [2, 6] # TODO What is the range?!
            else
              service_code = "73"
              # listed_rates = MI_PRIORITY_RATES
              range = [6,10]
            end

            mi_rate = options[:mi_rate] || 11.0
            rate = packages.sum(&:lbs) * mi_rate

            # "72" => "UPS Expedited Mail Innovations" # DOMESTIC # NOTE: We don't use this yet
            # "73" => "UPS Priority Mail Innovations" # INTL
            # "74" => "UPS Economy Mail Innovations" # INTL # NOTE: We don't use this yet
            unless error
              rate_estimates << RateEstimate.new(origin, destination, @@name,
                                  service_name_for(origin, service_code),
                                  :total_price => rate,
                                  :currency => 'USD',
                                  :service_code => service_code,
                                  :packages => packages,
                                  :delivery_range => range)
            end
          end
        end
        RateResponse.new(success, message, Hash.from_xml(response).values.first, :rates => rate_estimates, :xml => response, :request => last_request)
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

            # If this is a Mail Innovations EPL, we add in a 1px image
            # because it won't print otherwise
            # This is text generated from a PCX image
            # EX: IO.read("test.pcx").force_encoding("ISO-8859-1").encode("utf-8", replace: nil)
            # NOTE: Mail Innovations breaks from the UPS 1Z prefix on tracking numbers
            # if extension.downcase == 'epl' and package_labels.last[:tracking_number][0..1] != '1Z'
            #   package_labels.last[:label_file].write("\n\u0005\u0001\u0001\u0000\u0000\u0000\u0000\a\u0000\a\u0000H\u0000H\u0000\u000F\u000F\u000F\u000E\u000E\u000E\r\r\r\f\f\f\v\v\v\n\n\n\t\t\t\b\b\b\a\a\a\u0006\u0006\u0006\u0005\u0005\u0005\u0004\u0004\u0004\u0003\u0003\u0003\u0002\u0002\u0002\u0001\u0001\u0001\u0000\u0000\u0000\u0000\u0001\u0002\u0000\u0001\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000ÂÿÂÿÂÿÂÿÂÿÂÿÂÿÂÿ")
            # end

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

    def parse_void_response(response, tracking_numbers=[])
      xml = REXML::Document.new(response)
      success = response_success?(xml)
      message = response_message(xml)

      if tracking_numbers.length > 1
        status = true
        multiple_response = Hash.new
        xml.elements.each('//VoidShipmentResponse/PackageLevelResults') do |package_element|
          tracking_number = package_element.get_text("TrackingNumber").to_s
          response_code = package_element.get_text("StatusCode/Code").to_i
          multiple_response[tracking_number] = response_code
          status = false if response_code != 1
        end
        if status == true
          return true
        else
          return multiple_response
        end
      else
        status = xml.get_text('//VoidShipmentResponse/Response/ResponseStatusCode').to_s
        # TODO: we may need a more detailed error message in the event that one package is voided and the other isn't
        if status == '1'
          return true
        else
          return message
        end
      end
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
