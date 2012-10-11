module ActiveMerchant #:nodoc:
  module Shipping
    
    class LabelResponse < Response
      
      attr_reader :package_labels
      
      def initialize(success, message, params = {}, options = {})
        @package_labels = Array(options[:package_labels] || options[:packages] || options[:labels])
        super
      end
      
      alias_method :packages, :package_labels
      alias_method :labels, :package_labels
      
    end
    
  end
end