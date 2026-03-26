class LookupsController < ApplicationController
  # GET /lookups/companies
  def companies
    result = DocumentProcessing::Lookups::CompaniesFetcher.new.call
    render json: { companies: result }
  end

  # GET /lookups/users
  # Optional param: company
  def users
    company = params[:company]
    result = DocumentProcessing::Lookups::UsersFetcher.new.call(company: company)
    render json: { users: result.map { |u| { id: u.id, name: u.name, email: u.email, employee_code: u.employee_code } } }
  end
end
