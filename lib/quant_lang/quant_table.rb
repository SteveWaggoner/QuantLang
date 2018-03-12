#!ruby

def print_table(rows)

    if not rows.is_a? Array then raise "expected array but found #{rows}" end
    rows.each {|r| if not r.is_a? TableRow then raise "expected TableRow but found: #{r}" end }


    field_names = rows.map{|r| r.field_names}.flatten.uniq
    field_maxlen = field_names.map{|f| f.size}
    rows.each do |r|
        for i in 0...field_names.size
            l = r.field(field_names[i]).size
            if field_maxlen[i] < l
               field_maxlen[i] = l
            end
        end
    end

    head = '+' + field_maxlen.map{|len| '-' * (len + 2)}.join('+') + '+'
    puts head
    titles = field_names.each_with_index.map{|v,i| v.to_s + ' ' * (field_maxlen[i] - v.to_s.length) }
    puts '| ' + titles.join(' | ') + ' |'
    puts head

    rows.each do |r|
        row = field_names.map{|n|r.field(n)}.each_with_index.map{|v,i| v.to_s + ' ' * (field_maxlen[i] - v.to_s.length) }
        puts '| ' + row.join(' | ') + ' |'
    end
    puts head
end

class TableRow

    def initialize
        @field_names = []
        @field_values = {}
    end

    def set_field(name,value)
        @field_names << name
        @field_values[name] = value.to_s
    end

    def field_names
       @field_names
    end

    def field(name)
        (@field_values[name] || "")
    end

end


