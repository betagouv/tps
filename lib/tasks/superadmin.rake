require Rails.root.join("lib", "tasks", "task_helper")

namespace :superadmin do
  desc <<~EOD
    List all super-admins
  EOD
  task list: :environment do
    rake_puts "All SuperAdmins:"
    SuperAdmin.all.pluck(:email).each do |a|
      puts a
    end
  end

  desc <<~EOD
    Create a new super-admin account with the #EMAIL email address.
  EOD
  task :create, [:email] => :environment do |_t, args|
    email = args[:email]

    rake_puts "Creating SuperAdmin for #{email}"
    a = SuperAdmin.new(email: email, password: Devise.friendly_token)

    if a.save
      rake_puts "#{a.email} created"
      a.send_reset_password_instructions
      rake_puts "Password reset instructions sent to #{a.email}"
    else
      rake_puts "An error occured: #{a.errors.full_messages}"
    end
  end

  desc <<~EOD
    Delete the #EMAIL super-admin account
  EOD
  task :delete, [:email] => :environment do |_t, args|
    email = args[:email]
    rake_puts "Deleting SuperAdmin for #{email}"
    a = SuperAdmin.find_by(email: email)
    a.destroy
    rake_puts "#{a.email} deleted"
  end
end
