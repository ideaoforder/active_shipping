module ActiveMerchant #:nodoc:
  module Shipping #:nodoc:
    class CustomsInfo
      FORM_TYPES = %w{CN22}
      USPS_FORM_TYPES = {
        'CN22' => 'Form2976'
      }

      attr_reader :form_type,
                  :certify,
                  :signer,
                  :contents_type,
                  :label_size,
                  :gift,
                  :customs_items
      
      alias_method 'gift?', :gift
      alias_method 'certify?', :certify

      # We set some intuitive defaults here
      def initialize(options = {})
        @form_type = options[:form_type] || 'CN22'
        @certify = options[:certify] || false
        @signer = options[:signer]
        @gift = options[:gift] || false
        @contents_type = @gift ? 'GIFT' : 'MERCHANDISE'
        @label_size = options[:label_size]
        @customs_items = Array(options[:customs_items])
      end

      def usps_form_type
        USPS_FORM_TYPES[@form_type]
      end

    end
      
  end
end
