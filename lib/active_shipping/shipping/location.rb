module ActiveMerchant #:nodoc:
  module Shipping #:nodoc:
    class Location
      ADDRESS_TYPES = %w{residential commercial po_box}

      STATES = {"al" => "alabama", "ne" => "nebraska", "ak" => "alaska", "nv" => "nevada", "az" => "arizona", "nh" => "new hampshire", "ar" => "arkansas", "nj" => "new jersey", "ca" => "california", "nm" => "new mexico", "co" => "colorado", "ny" => "new york", "ct" => "connecticut", "nc" => "north carolina", "de" => "delaware", "nd" => "north dakota", "fl" => "florida", "oh" => "ohio", "ga" => "georgia", "ok" => "oklahoma", "hi" => "hawaii", "or" => "oregon", "id" => "idaho", "pa" => "pennsylvania", "il" => "illinois", "pr" => "puerto rico", "in" => "indiana", "ri" => "rhode island", "ia" => "iowa", "sc" => "south carolina", "ks" => "kansas", "sd" => "south dakota", "ky" => "kentucky", "tn" => "tennessee", "la" => "louisiana", "tx" => "texas", "me" => "maine", "ut" => "utah", "md" => "maryland", "vt" => "vermont", "ma" => "massachusetts", "va" => "virginia", "mi" => "michigan", "wa" => "washington", "mn" => "minnesota", "dc" => "district of columbia", "ms" => "mississippi", "wv" => "west virginia", "mo" => "missouri", "wi" => "wisconsin", "mt" => "montana", "wy" => "wyoming",  "bc" => "british columbia", "ab" => "alberta", "sk" => "saskatchewan", "yt" => "yukon", "ns" => "nova scotia", "nt" => "northwest territories", "qc" => "quebec", "nu" => "nunavut", "nl" => "newfoundland and labrador", "on" => "ontario", "nb" => "new brunswick", "mb" => "manitoba", "pe" => "prince edward island"}

      attr_reader :options,
                  :country,
                  :postal_code,
                  :province,
                  :city,
                  :name,
                  :address1,
                  :address2,
                  :address3,
                  :phone,
                  :fax,
                  :address_type,
                  :company_name,
                  :attention_name,
                  :email,
                  :tax_id
      
      alias_method :zip, :postal_code
      alias_method :postal, :postal_code
      alias_method :state, :province
      alias_method :territory, :province
      alias_method :region, :province
      alias_method :company, :company_name
      alias_method :attention, :attention_name
      alias_method :tax_identification_number, :tax_id
      alias_method :email_address, :email
      
      def initialize(options = {})
        @country = (options[:country].nil? or options[:country].is_a?(ActiveMerchant::Country)) ?
                      options[:country] :
                      ActiveMerchant::Country.find(options[:country])
        @postal_code = options[:postal_code] || options[:postal] || options[:zip]
        @province = options[:province] || options[:state] || options[:territory] || options[:region]
        # if a users submits a full state or province name
        @province = STATES.has_value?(@province.downcase) ? STATES.index(@province.downcase).upcase : @province.upcase unless @province.blank?
        # TODO: we could add a zipcode lookup here too, in the event that there's a misspelling/missing state
        # For now, we'll provide a method, so users can validate themselves
        @city = options[:city]
        @name = options[:name]
        @address1 = options[:address1]
        @address2 = options[:address2]
        @address3 = options[:address3]
        @phone = options[:phone]
        @fax = options[:fax]
        @company_name = options[:company_name] || options[:company]
        @attention_name = options[:attention_name] || options[:attention]
        @tax_id = options[:tax_id] || options[:tax_identification_number]
        @email = options[:email] || options[:email_address]

        self.address_type = options[:address_type]
      end
      
      def self.from(object, options={})
        return object if object.is_a? ActiveMerchant::Shipping::Location
        attr_mappings = {
          :name => [:name],
          :country => [:country_code, :country],
          :postal_code => [:postal_code, :zip, :postal],
          :province => [:province_code, :state_code, :territory_code, :region_code, :province, :state, :territory, :region],
          :city => [:city, :town],
          :address1 => [:address1, :address, :street],
          :address2 => [:address2],
          :address3 => [:address3],
          :phone => [:phone, :phone_number],
          :fax => [:fax, :fax_number],
          :address_type => [:address_type],
          :company_name => [:company, :company_name],
          :attention_name => [:attention, :attention_name],
          :email => [:email, :email_address],
          :tax_id => [:tax_id, :tax_identification_number]
        }
        attributes = {}
        hash_access = begin
          object[:some_symbol]
          true
        rescue
          false
        end
        attr_mappings.each do |pair|
          pair[1].each do |sym|
            if value = (object[sym] if hash_access) || (object.send(sym) if object.respond_to?(sym) && (!hash_access || !Hash.public_instance_methods.include?(sym.to_s)))
              attributes[pair[0]] = value
              break
            end
          end
        end
        attributes.delete(:address_type) unless ADDRESS_TYPES.include?(attributes[:address_type].to_s)
        self.new(attributes.update(options))
      end
      
      def country_code(format = :alpha2)
        @country.nil? ? nil : @country.code(format).value
      end
      
      def residential?; @address_type == 'residential' end
      def commercial?; @address_type == 'commercial' end
      def po_box?; @address_type == 'po_box' end

      def address_type=(value)
        return unless value.present?
        raise ArgumentError.new("address_type must be one of #{ADDRESS_TYPES.join(', ')}") unless ADDRESS_TYPES.include?(value.to_s)
        @address_type = value.to_s
      end

      def to_hash
        {
          :country => country_code,
          :postal_code => postal_code,
          :province => province,
          :city => city,
          :name => name,
          :address1 => address1,
          :address2 => address2,
          :address3 => address3,
          :phone => phone,
          :fax => fax,
          :address_type => address_type,
          :company_name => company_name,
          :attention_name => attention_name,
          :tax_id => tax_id,
          :email => email
        }
      end

      def to_xml(options={})
        options[:root] ||= "location"
        to_hash.to_xml(options)
      end

      def to_s
        prettyprint.gsub(/\n/, ' ')
      end
      
      def prettyprint
        chunks = []
        chunks << [@name, @address1,@address2,@address3].reject {|e| e.blank?}.join("\n")
        chunks << [@city,@province,@postal_code].reject {|e| e.blank?}.join(', ')
        chunks << @country
        chunks.reject {|e| e.blank?}.join("\n")
      end
      
      def inspect
        string = prettyprint
        string << "\nPhone: #{@phone}" unless @phone.blank?
        string << "\nFax: #{@fax}" unless @fax.blank?
        string
      end

      # Returns the postal code as a properly formatted Zip+4 code, e.g. "77095-2233"
      def zip_plus_4
        if /(\d{5})(\d{4})/ =~ @postal_code
          return "#{$1}-#{$2}"
        elsif /\d{5}-\d{4}/ =~ @postal_code
          return @postal_code
        else
          nil
        end
      end

      # Returns the first 5 digits of the postal code, e.g. "77095"
      def zip5
        @postal_code.to_s.scan(/\d{5}/).first || zip
      end

      # Returns the last 4 digits of the postal code
      def zip4
        if /(\d{5})(\d{4})/ =~ @postal_code
          return "#{$2}"
        elsif /\d{5}-\d{4}/ =~ @postal_code
          return "#{$2}"
        else
          return nil
        end
      end

      # TODO: We should have a province from zip method too
      def self.state_from_zip(zip)
        zip = zip.to_i
        {
          (99500...99929) => "AK", 
          (35000...36999) => "AL", 
          (71600...72999) => "AR", 
          (75502...75505) => "AR", 
          (85000...86599) => "AZ", 
          (90000...96199) => "CA", 
          (80000...81699) => "CO", 
          (6000...6999) => "CT", 
          (20000...20099) => "DC", 
          (20200...20599) => "DC", 
          (19700...19999) => "DE", 
          (32000...33999) => "FL", 
          (34100...34999) => "FL", 
          (30000...31999) => "GA", 
          (96700...96798) => "HI", 
          (96800...96899) => "HI", 
          (50000...52999) => "IA", 
          (83200...83899) => "ID", 
          (60000...62999) => "IL", 
          (46000...47999) => "IN", 
          (66000...67999) => "KS", 
          (40000...42799) => "KY", 
          (45275...45275) => "KY", 
          (70000...71499) => "LA", 
          (71749...71749) => "LA", 
          (1000...2799) => "MA", 
          (20331...20331) => "MD", 
          (20600...21999) => "MD", 
          (3801...3801) => "ME", 
          (3804...3804) => "ME", 
          (3900...4999) => "ME", 
          (48000...49999) => "MI", 
          (55000...56799) => "MN", 
          (63000...65899) => "MO", 
          (38600...39799) => "MS", 
          (59000...59999) => "MT", 
          (27000...28999) => "NC", 
          (58000...58899) => "ND", 
          (68000...69399) => "NE", 
          (3000...3803) => "NH", 
          (3809...3899) => "NH", 
          (7000...8999) => "NJ", 
          (87000...88499) => "NM", 
          (89000...89899) => "NV", 
          (400...599) => "NY", 
          (6390...6390) => "NY", 
          (9000...14999) => "NY", 
          (43000...45999) => "OH", 
          (73000...73199) => "OK", 
          (73400...74999) => "OK", 
          (97000...97999) => "OR", 
          (15000...19699) => "PA", 
          (2800...2999) => "RI", 
          (6379...6379) => "RI", 
          (29000...29999) => "SC", 
          (57000...57799) => "SD", 
          (37000...38599) => "TN", 
          (72395...72395) => "TN", 
          (73300...73399) => "TX", 
          (73949...73949) => "TX", 
          (75000...79999) => "TX", 
          (88501...88599) => "TX", 
          (84000...84799) => "UT", 
          (20105...20199) => "VA", 
          (20301...20301) => "VA", 
          (20370...20370) => "VA", 
          (22000...24699) => "VA", 
          (5000...5999) => "VT", 
          (98000...99499) => "WA", 
          (49936...49936) => "WI", 
          (53000...54999) => "WI", 
          (24700...26899) => "WV", 
          (82000...83199) => "WY"
          }.each do |range, state|
          return state if range.include? zip
        end
        raise ArgumentError, "Invalid zip code"
      end

    end
      
  end
end
