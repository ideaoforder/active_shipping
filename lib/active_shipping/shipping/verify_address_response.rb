module ActiveMerchant #:nodoc:
  module Shipping
    
    class VerifyAddressResponse < Response
      
      attr_reader :zip5,
                  :zip4,
                  :state,
                  :city,
                  :address1,
                  :address2,
                  :company_name,
                  :country,
                  :success,
                  :message
      
      def initialize(success, message, address = {}, options = {})
        @zip5 = address[:zip5]
        @zip4 = address[:zip4]
        @state = address[:state]
        @city = address[:city]
        @address1 = address[:address1]
        @address2 = address[:address2]
        @company_name = address[:company_name] || address[:firm_name]
        @country = address[:country]
        @message = message
        @success = success
        super
      end
      
    end
    
  end
end