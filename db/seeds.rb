# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

puts "Svuotando il database..."
Employee.destroy_all

puts "Creando impiegati fittizi..."
10.times do
  Employee.create!(
    name: Faker::Name.name,
    email: Faker::Internet.email,
    employee_code: "EMP#{rand(1000..9999)}"
  )
end

# Aggiungiamo un utente specifico per i nostri test
Employee.create!(name: "Mario Rossi", email: "mario.rossi@azienda.it", employee_code: "EMP0001")

puts "Creati #{Employee.count} impiegati."