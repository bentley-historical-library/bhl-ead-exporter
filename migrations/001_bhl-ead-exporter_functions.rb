require 'db/migrations/utils'

#Converted all SQL functions to start with BHL_ to prevent conflicts with ArchivesSpace

Sequel.migration do
  up do
    if $db_type == :mysql


# Function to return enum value given an id
run "DROP  FUNCTION IF EXISTS BHL_GetEnumValue;"
run <<EOF
CREATE FUNCTION BHL_GetEnumValue(f_enum_id INT) 
    RETURNS VARCHAR(255)
    READS SQL DATA
BEGIN
    DECLARE f_value VARCHAR(255);   
    SELECT enumeration_value.`value`INTO f_value
    FROM enumeration_value
    WHERE enumeration_value.`id` = f_enum_id;
    RETURN f_value;
END 
EOF

# Function to return the enum value with the first letter capitalize
run "DROP  FUNCTION IF EXISTS BHL_GetEnumValueUF;"
run <<EOF
CREATE FUNCTION BHL_GetEnumValueUF(f_enum_id INT) 
    RETURNS VARCHAR(255)
    READS SQL DATA
BEGIN
    DECLARE f_value VARCHAR(255);   
    DECLARE f_ovalue VARCHAR(255);        
        SET f_ovalue = BHL_GetEnumValue(f_enum_id);
    SET f_value = CONCAT(UCASE(LEFT(f_ovalue, 1)), SUBSTRING(f_ovalue, 2));
    RETURN f_value;
END 
EOF


    end
  end
end