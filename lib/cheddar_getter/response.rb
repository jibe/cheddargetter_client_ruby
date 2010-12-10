module CheddarGetter
  class Response
    SPECIAL_ARRAY_KEYS = {
      :plans => :plan, 
      :items => :item,
      :subscriptions => :subscription,
      :customers => :customer,
      :invoices => :invoice,
      :charges => :charge,
      :transactions => :transaction,
      :errors => :error
    }
    
    KEY_TO_DATA_TYPE = { 
      :isActive => :boolean,
      :isFree => :boolean,
      :trialDays => :integer,
      :setupChargeAmount => :float,
      :recurringChargeAmount => :float,
      :billingFrequencyQuantity => :integer,
      :createdDatetime => :datetime,
      :quantityIncluded => :float,
      :isPeriodic => :boolean,
      :overageAmount => :float,
      :isVatExempt => :boolean,
      :firstContactDatetime => :datetime,
      :modifiedDatetime => :datetime,
      :canceledDatetime => :datetime,
      :ccExpirationDate => :date,
      :quantity => :float,
      :billingDatetime => :datetime,
      :eachAmount => :float,
      :number => :integer,
      :amount => :float,
      :transactedDatetime => :datetime,
      :vatRate => :float
    }
    
    attr_accessor :raw_response, :clean_response
    
    def initialize(response)    #:nodoc:
      self.raw_response = response
      create_clean_response
    end
    
    [:errors, :plans, :customers].each do |key|
      define_method key.to_s do
        self[key]
      end
    end
    
    #true if the response from CheddarGetter was valid
    def valid?
      self.errors.size == 0 && self.raw_response.code < 400
    end
    
    #the error messages (if there were any) if the CheddarGetter response was invalid
    def error_messages
      self.errors.map do |e|
        msg = nil
        if e
          msg = e[:text]
          msg += ": #{e[:fieldName]}" unless e[:fieldName].blank?
        end
        msg
      end
    end
    
    #Returns the given plan.
    #
    #code must be provided if this response contains more than one plan.
    def plan(code = nil)
      retrieve_item(self, :plans, code)
    end
    
    #Returns the items for the given plan.
    #
    #code must be provided if this response contains more than one plan.
    def plan_items(code = nil)
      (plan(code) || { })[:items]
    end
    
    #Returns the given item for the given plan.
    #
    #item_code must be provided if the plan has more than one item.
    #
    #code must be provided if this response contains more than one plan.
    def plan_item(item_code = nil, code = nil)
      retrieve_item(plan(code), :items, item_code)
    end
    
    #Returns the given customer.
    #
    #code must be provided if this response contains more than one customer.
    def customer(code = nil)
      retrieve_item(self, :customers, code)
    end
    
    #Returns the current subscription for the given customer.
    #
    #code must be provided if this response contains more than one customer.
    def customer_subscription(code = nil)
      #current subscription is always the first one
      (customer_subscriptions(code) || []).first
    end
    
    #Returns all the subscriptions for the given customer.  
    #Only the first one is active, the rest is historical.
    #
    #code must be provided if this response contains more than one customer.
    def customer_subscriptions(code = nil)
      (customer(code) || { })[:subscriptions]
    end
    
    #Returns the current plan for the given customer
    #
    #code must be provided if this response contains more than one customer.
    def customer_plan(code = nil)
      ((customer_subscription(code) || { })[:plans] || []).first
    end
    
    #Returns the current open invoice for the given customer.
    #
    #code must be provided if this response contains more than one customer.
    def customer_invoice(code = nil)
      #current invoice is always the first one
      ((customer_subscription(code) || { })[:invoices] || []).first
    end
    
    #Returns all of the invoices for the given customer.
    #
    #code must be provided if this response contains more than one customer.
    def customer_invoices(code = nil)
      (customer_subscriptions(code) || []).map{ |s| s[:invoices] || [] }.flatten
    end
    
    #Returns the last billed invoice for the given customer.
    #This is not the same as the currect active invoice.
    #
    #nil if there is no last billed invoice.
    #
    #code must be provided if this response contains more than one customer.
    def customer_last_billed_invoice(code = nil)
      #last billed invoice is always the second one
      (customer_invoices(code) || [])[1]
    end
    
    #Returns all of the transactions for the given customer.
    #
    #code must be provided if this response contains more than one customer.
    def customer_transactions(code = nil)
      customer_invoices(code).map{ |s| s[:transactions] || [] }.flatten
    end
    
    #Returns the last transaction for the given customer.
    #
    #nil if there are no transactions.
    #
    #code must be provided if this response contains more than one customer.
    def customer_last_transaction(code = nil)
      invoice = customer_last_billed_invoice(code) || { }
      (invoice[:transactions] || []).first
    end
    
    #Returns an array of any currently outstanding invoices for the given customer.
    #
    #code must be provided if this response contains more than one customer.
    def customer_outstanding_invoices(code = nil)
      now = DateTime.now
      customer_invoices(code).reject do |i| 
        i[:paidTransactionId] || i[:billingDatetime] > now
      end
    end
    
    #Info about the given item for the given customer.  
    #Merges the plan item info with the subscription item info.
    #
    #item_code must be provided if the customer is on a plan with more than one item.
    #
    #code must be provided if this response contains more than one customer.
    def customer_item(item_code = nil, code = nil)
      sub = customer_subscription(code)
      return nil unless sub
      sub_item = retrieve_item(sub, :items, item_code)
      plan_item = retrieve_item(retrieve_item(sub, :plans), :items, item_code)
      return nil unless sub_item && plan_item
      item = plan_item.dup
      item[:quantity] = sub_item[:quantity]
      item
    end
    
    #The amount remaining for a given item for a given customer.
    #
    #item_code must be provided if the customer is on a plan with more than one item.
    #
    #code must be provided if this response contains more than one customer.
    def customer_item_quantity_remaining(item_code = nil, code = nil)
      item = customer_item(item_code, code)
      item ? item[:quantityIncluded] - item[:quantity] : 0
    end
    
    #The overage amount for the given item for the given customer.  0 if they are still under their limit.
    #
    #item_code must be provided if the customer is on a plan with more than one item.
    #
    #code must be provided if this response contains more than one customer.
    def customer_item_quantity_overage(item_code = nil, code = nil)
      over = -customer_item_quantity_remaining(item_code, code)
      over = 0 if over <= 0
      over
    end
    
    #The current overage cost for the given item for the given customer.
    #
    #item_code must be provided if the customer is on a plan with more than one item.
    #
    #code must be provided if this response contains more than one customer.
    def customer_item_quantity_overage_cost(item_code = nil, code = nil)
      item = customer_item(item_code, code)
      return 0 unless item
      overage = customer_item_quantity_overage(item_code, code)
      item[:overageAmount] * overage
    end
    
    #true if the customer is canceled
    #
    #code must be provided if this reponse contains more than one customer
    def customer_canceled?(code = nil)
      sub = customer_subscription(code)
      sub ? !!sub[:canceledDatetime] : nil
    end
    
    #access the root keys of the response directly, such as 
    #:customers, :plans, or :error
    def [](value)
      self.clean_response[value]
    end
    
    
    private
    def deep_fix_array_keys!(data)
      if data.is_a?(Array)
        data.each do |v|
          deep_fix_array_keys!(v)
        end
      elsif data.is_a?(Hash)
        data.each do |k, v|
          deep_fix_array_keys!(v)
          sub_key = SPECIAL_ARRAY_KEYS[k]
          if sub_key && v.is_a?(Hash) && v.keys.size == 1 && v[sub_key]
            data[k] = v = [v[sub_key]].flatten
          end
        end
      end
    end
    
    def deep_symbolize_keys!(data)
      if data.is_a?(Array)
        data.each do |v|
          deep_symbolize_keys!(v) 
        end
      elsif data.is_a?(Hash)
        data.keys.each do |key|
          deep_symbolize_keys!(data[key]) 
          data[(key.to_sym rescue key) || key] = data.delete(key)
        end
      end
    end
    
    def deep_fix_data_types!(data)
      if data.is_a?(Array)
        data.each do |v|
          deep_fix_data_types!(v) 
        end
      elsif data.is_a?(Hash)
        data.each do |k, v|
          deep_fix_data_types!(v)
          type = KEY_TO_DATA_TYPE[k]
          if type && v.is_a?(String)
            data[k] = case type
                        when :integer then v.to_i
                        when :float then v.to_f
                        when :datetime then DateTime.parse(v) rescue v
                        when :date then Date.parse(v) rescue v
                        when :boolean then v.to_i != 0
                        else v
                        end
          end
        end
      end
    end
    
    def reduce_clean_errors!(data)
      root_plural    = [(data.delete(:errors) || { })[:error]].flatten
      root_singular  = [data.delete(:error)]
      embed_singluar = []
      embed_plural   = []
      embed = data[:customers] || data[:plans]
      if embed
        embed_singluar = [(embed.delete(:errors) || { })[:error]].flatten
        embed_plural   = [embed.delete(:error)]
      end
      new_errors = (root_plural + root_singular + embed_plural + embed_singluar).compact
      data[:errors] = new_errors
    end
    
    def create_clean_response
      data = self.raw_response.parsed_response.is_a?(Hash) ? self.raw_response.parsed_response : { }
      deep_symbolize_keys!(data)
      reduce_clean_errors!(data)
      deep_fix_array_keys!(data)
      deep_fix_data_types!(data)
      self.clean_response = data
      
      #because Crack can:t get attributes and text at the same time.  grrrr
      unless self.valid?
        data = Crack::XML.parse(self.raw_response.body.gsub(/<error(.*)>(.*)<\/error>/, 
                                                            '<error\1><text>\2</text></error>'))
        deep_symbolize_keys!(data)
        reduce_clean_errors!(data)
        deep_fix_array_keys!(data)
        deep_fix_data_types!(data)
        self.clean_response = data
        self.errors.each do |e|
          aux_code = (e[:auxCode] || "")
          if aux_code[":"]
            split_aux_code = aux_code.split(':')
            e[:fieldName] = split_aux_code.first
            e[:errorType] = split_aux_code.last
          end          
        end

      end
      
    end
    
    def retrieve_item(hash, type, code = nil)
      array = hash[type]
      if !array
        raise CheddarGetter::ResponseException.new(
          "Can:t get #{type} from a response that doesn:t contain #{type}")
      elsif code
        code = code.to_s
        array.detect{ |p| p[:code].to_s == code }
      elsif array.size <= 1
        array.first
      else
        raise CheddarGetter::ResponseException.new(
          "This response contains multiple #{type} so you need to provide the code for the one you wish to get")
      end
    end
  end
end
