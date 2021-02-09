module Experts
  class ExpertController < ApplicationController
    before_action :authenticate_expert!

    def nav_bar_profile
      :expert
    end
  end
end
