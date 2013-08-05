module ActiveMerchant #:nodoc:
  module Shipping
      
    class CustomsItem
      attr_reader :quantity, :weight, :value, :description

      def initialize(options = {})
      	@quantity = options[:quantity]
      	@weight = options[:weight] 
      	@value = options[:value] 
      	@description = options[:description]
      end
      
    end
    
  end
end