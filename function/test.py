import psycopg2


#Connect to the cluster
conn = psycopg2.connect(
    host='mydb.cgbbluvj78rn.us-east-1.rds.amazonaws.com',
    port=5432,
    user='test',
    password='test'
)

# Create a Cursor object
cursor = conn.cursor()
# Query a table using the Cursor
cursor.execute("select 1")
#Retrieve the query result set
result = cursor.fetchall()
print(result)  