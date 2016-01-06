class UserController < ApplicationController
	PAST_QUARTER_CUTOFF = Time.new(2016, 1, 1, 0, 0)
	before_action :ensure_user

	def show
		#events = current_user.attending_events.where('end_time >= ?', Time.now).order(:start_time)
		attendances = Attendance.where(user_id: @user.id)
		@attended_events = attendances.map{|x| Event.find(x.event_id)}.select{|x| x.end_time > PAST_QUARTER_CUTOFF }
    @events = @attended_events.any? ? @attended_events.group_by{|x| x.start_time.strftime("%m/%d (%A)")} : nil
		# how can I make this prettier
		@hours = 0
		@flakehours = 0
		@fellowships = 0
		@user.attendances.each do |a|
			event = Event.find(a.event_id)
			if event.end_time > PAST_QUARTER_CUTOFF
				if event.event_type == "Service"
					if a.attended?
						@hours += a.drove ? event.driver_hours : event.hours
					elsif event.flake_penalty? && a.flaked?
						@flakehours += event.hours
					end
				elsif event.event_type == "Fellowship" && a.attended?
					@fellowships += 1
				end
			end
		end
	end

	def greensheet
    @hours = 0 
    @fellowships = 0
    @ics = 0
    @family = 0
    @rush = 0
    @fundraise = 0
    @interviewparties = 0
    @infonights = 0
    @flyering = 0
    @chalkboarding = 0

    @texts = GreensheetText.where(user_id: @user.id) #comment sections
    unless @texts.any? #initialize comment sections
      #modify titles/descriptions in app/models/greensheet_text.rb file
      GreensheetText.titles.zip(GreensheetText.descriptions).each do |t,d|

        gtext = GreensheetText.create(user_id: @user.id, title: t,
                                      description: d)
        @texts.push(gtext) unless @texts.include?(gtext)#avoid duplicate problem

      end
    end

    if request.patch?
      if @user.update(greensheet_sections_attributes: params[:user][:greensheet_sections_attributes])
         if @user.update(greensheet_texts_attributes: params[:user][:greensheet_texts_attributes])
           flash[:success] = "Greensheet successfully updated."
         end
      else
        flash[:alert] = "There may have been problems saving."
      end
      
      @sections = GreensheetSection.where(user_id: @user.id)
    end #end request.patch?

    if request.get?
      @sections = GreensheetSection.where(user_id: @user.id)
      @sections ||= [] #no saved sections yet

      attendances = Attendance.where(user_id: @user.id)
      
      @user.attendances.where(past_quarter: false).each do |a|
        event = Event.find(a.event_id)
        
        dont_add = false 
        #@sections already has that event, or no attendance

        #accounts for flaking and all
        hours = GreensheetSection.calculateHours(a, event)

        if ["Alpha", "Phi", "Omega", "Rho", "Pi"].include? event.event_type
          event.event_type = "Family" #list family for dropdown
        end

        chair = User.find_by(id: event.chair_id).displayname
        chair ||= "No Chair"

        #already exists, may be event changes
        gsheet = GreensheetSection.find_by(event_id: a.event_id, 
                                           user_id: @user.id) 
        if gsheet
          dont_add = true
          gsheet.update_attributes(title: event.title, hours: hours,
            chair: chair,
            event_type: event.event_type)
        end

        dont_add = true if !a.attended && !a.flaked #no show but no consequence
        dont_add = true if a.flaked && !event.flake_penalty #no consequence
          
        unless dont_add
          @sections.push(GreensheetSection.create( user_id: @user.id, 
                                                   title: event.title,
                                                   start_time: event.start_time,
                                                   hours: hours,
                                                   chair: chair,
                                                   event_type: event.event_type,
                                          original_event_type: event.event_type,
                                          event_id: event.id
          ))
        end
      end
    end #of the request.get? 

    @sections = @sections.uniq #rid of more duplicate problems

    @sections.each do |s|
      case s.event_type
      when "Service"
        @hours += s.hours
      when "Fellowship"
        @fellowships += s.hours
      when "Interchapter"
        @ics += s.hours
      when "Family"
        @family += s.hours
      when "Rush"
        @rush += s.hours
      when "Fundraising"
        @fundraise += s.hours
      when "Other"
        @interviewparties += 1 if s.title.include? "Interview"
        @infonights += 1 if s.title.include? "Info"
        @flyering += 1 if s.title.include? "Flyering"
        @chalkboarding += 1 if s.title.include? "Chalkboard"
      end
    end

    if request.patch?
      render 'greensheet'
    end

	end

	def update
		@edit = true
		updater = current_user.id
		if request.patch?
			user_params[:firstname].strip!
			user_params[:lastname].strip!
			if @user.update_attributes(user_params)
				@user.update_attribute(:displayname, user_params[:firstname] + ' ' + user_params[:lastname])
				if updater == @user.id
					sign_in(@user, :bypass => true)
				end
				if !request.xhr?
					flash[:success] = "Profile successfully updated."
					render 'update'
				end
			elsif !request.xhr?
				flash[:alert] = "There may have been errors saving."
				render 'update'
			end
		end
	end

	def all
		unless current_user.admin?
			flash[:alert] = "You do not have permission to access that page."
			redirect_to root_path
		end
		@users = User.order('created_at DESC').where(approved: true)
	end

	private

	def user_params
    params.require(:user).permit(:name, :email, :password, :firstname, :lastname, :nickname, :displayname,
      :phone, :family, :line, :pledge_class, :membership_status, :major, :graduation_year, :shirt_size, :car,
      :password, :password_confirmation)
	end

	def ensure_user
		@user = User.find_by_a_username(params[:id])
		@user ||= User.find(params[:id])
    unless user_signed_in? && (current_user.id == @user.id || current_user.admin)
      redirect_to root_path, notice: "You do not have permission to see that page."
    end
  end

end
