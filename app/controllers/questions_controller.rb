class QuestionsController < ApplicationController
  include ActionView::Helpers::TextHelper
  require 'crack'
  #caches_page :results
  
  # GET /questions
  # GET /questions.xml
  def index
    @meta = '<META NAME="ROBOTS" CONTENT="NOINDEX, NOFOLLOW">'
    @questions = Question.find(:all)

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @questions }
    end
  end

  # GET /questions/1
  # GET /questions/1.xml
  # def show
  #   @question = Question.find(params[:id])
  # 
  #   respond_to do |format|
  #     format.html # show.html.erb
  #     format.xml  { render :xml => @question }
  #   end
  # end
  def results
    @meta = '<META NAME="ROBOTS" CONTENT="NOINDEX, NOFOLLOW">'
    logger.info "@question = Question.find_by_name(#{params[:id]}) ..."
    @question = Question.find_by_name(params[:id], true)
    @question_id = @question.id
    @earl = Earl.find params[:id]
    logger.info "@question is #{@question.inspect}."
    @partial_results_url = "#{@earl.name}/results"
    if params[:all]
      @choices = Choice.find(:all, :params => {:question_id => @question_id})
    else
      @choices = Choice.find(:all, :params => {:question_id => @question_id, :limit => 10, :offset => 0})
    end
    logger.info "First choice is #{@choices.first.inspect}"
  end
  
  def admin
    authenticate
    @meta = '<META NAME="ROBOTS" CONTENT="NOINDEX, NOFOLLOW">'
    logger.info "@question = Question.find_by_name(#{params[:id]}) ..."
    @question = Question.find_by_name(params[:id])
    @earl = Earl.find params[:id]

    
    logger.info "@question is #{@question.inspect}."
    logger.info "@earl is #{@earl.inspect}."
    @partial_results_url = "#{@earl.name}/results"
    @choices = Choice.find(:all, :params => {:question_id => @question.id, :include_inactive => true})
    logger.info "First choice is #{@choices.first.inspect}"
  end
  
  def vote(direction)
    expire_page :action => :results
    prompt_id = session[:current_prompt_id]
    logger.info "Getting ready to vote left on Prompt #{prompt_id}, Question #{params[:id]}"
    @prompt = Prompt.find(prompt_id, :params => {:question_id => params[:id]})
    case direction
    when :left
      winner, loser = @prompt.left_choice_text, @prompt.right_choice_text
      conditional = p = @prompt.post(:vote_left, :params => {'auto' => request.session_options[:id]})
    when :right
      loser, winner = @prompt.left_choice_text, @prompt.right_choice_text
      conditional = p = @prompt.post(:vote_right, :params => {'auto' => request.session_options[:id]})
    else
      raise "unspecified choice"
    end
    session[:has_voted] = true
    logger.info "winnder [sic] was #{winner}, loser is #{loser}"
    logger.info "prompt was #{@prompt.inspect}"
    respond_to do |format|
        format.xml  {  head :ok }
        format.js  { 
          if conditional
            #flash[:notice] = 'Vote was successfully counted.'
            newprompt = Crack::XML.parse(p.body)['prompt']
            logger.info "newprompt is #{newprompt.inspect}"
            session[:current_prompt_id] = newprompt['id']
            #@newprompt = Question.find(params[:id])
            render :json => {:votes => 20, :newleft => truncate((newprompt['left_choice_text']), :length => 137), 
                             :newright => truncate((newprompt['right_choice_text']), :length => 137)
                             }.to_json
          else
            render :json => '{"error" : "Vote failed"}'
          end
          }
      end
  end
  
  def vote_left
    expire_page :action => :results
    vote(:left)
  end
  
  def vote_right
    expire_page :action => :results
    vote(:right)
  end
    
  def skip
    expire_page :action => :results
    prompt_id = session[:current_prompt_id]
    logger.info "Getting ready to skip out on Prompt #{prompt_id}, Question #{params[:id]}"
    @prompt = Prompt.find(prompt_id, :params => {:question_id => params[:id]})
    #raise Prompt.find(:all).inspect
    respond_to do |format|
        flash[:notice] = 'You just skipped.'
        format.xml  {  head :ok }
        format.js  { 
          if p = @prompt.post(:skip, :params => {'auto' => request.session_options[:id]})
            newprompt = Crack::XML.parse(p.body)['prompt']
            session[:current_prompt_id] = newprompt['id']
            @newprompt = Question.find(params[:id])
            render :json => {:votes => 20, :newleft => truncate(h(newprompt['left_choice_text']), :length => 137), :newright => truncate(h(newprompt['right_choice_text']), :length => 137)}.to_json
          else
            render :json => '{"error" : "Skip failed"}'
          end
          }
      end
    end

    def add_idea
      prompt_id = session[:current_prompt_id]
      logger.info "Getting ready to add an idea while viewing on Prompt #{prompt_id}, Question #{params[:id]}"
      new_idea_data = params[:new_idea]
      @choice = Choice.new(:data => new_idea_data)
      respond_to do |format|
          #flash[:notice] = 'You just added an idea for people to vote on.'
          format.xml  {  head :ok }
          format.js  { 
            the_params = {'auto' => request.session_options[:id], :data => new_idea_data, :question_id => params[:id]}
            the_params.merge!(:local_identifier => current_user.id) if signed_in?
            if p = Choice.post(:create_from_abroad, :question_id => params[:id], :params => the_params)
              logger.info "just posted to 'create from abroad', response pending"
              newchoice = Crack::XML.parse(p.body)['choice']
              logger.info "response is #{newchoice.inspect}"
              @question = Question.find(params[:id])
              render :json => {:votes => 20,
                               :choice_status => newchoice['choice_status'], 
                               :message => "You just added an idea for people to vote on: #{new_idea_data}"}.to_json
              case newchoice['choice_status']
              when 'inactive'
                ::IdeaMailer.deliver_notification @question.creator, @question, params[:id], new_idea_data, newchoice['saved_choice_id'] #spike
              when 'active'
                ::IdeaMailer.deliver_notification_for_active @question.creator, @question, params[:id], new_idea_data, newchoice['saved_choice_id']
              end
              #notification(user, question, question_id, choice, choice_id)
            else
              render :json => '{"error" : "Addition of new idea failed"}'
            end
            }
        end
      end
      
      def toggle
        authenticate
        expire_page :action => :results
        @earl = Earl.find(params[:id])
        unless current_user.owns? @earl
          render(:json => {:message => "You've just deactivated your question, #{params[:id]}"}.to_json) and return
        end
        logger.info "Getting ready to change active status of Question #{params[:id]} to #{!@earl.active?}"
        
        respond_to do |format|
            format.xml  {  head :ok }
            format.js  { 
              @earl.active = !(@earl.active)
              verb = @earl.active ? 'Activated' : 'Deactivated'
              if @earl.save!
                logger.info "just #{verb} question"
                render :json => {:message => "You've just #{verb.downcase} your question", :verb => verb}.to_json
              else
                render :json => {:message => "You've just #{verb.downcase} your question", :verb => verb}.to_json
              end
            }
        end
      end

   def toggle_autoactivate
        authenticate
        @earl = Earl.find_by_question_id(params[:id])
	@question = @earl.question
        unless current_user.owns? @earl
          render(:json => {:message => "Succesfully changed settings, #{params[:id]}"}.to_json) and return
        end
        logger.info "Getting ready to change idea autoactivate status of Question #{params[:id]} to #{!@question.it_should_autoactivate_ideas?}"
        
        respond_to do |format|
            format.xml  {  head :ok }
            format.js  { 
	      logger.info("Question is: #{@question.inspect}")
              new_activate_val = !(@question.it_should_autoactivate_ideas)
              verb = new_activate_val ? 'Enabled' : 'Disabled'
	      logger.info("Question is: #{@question.inspect}")
              if @question.put(:set_autoactivate_ideas_from_abroad, :question => { :it_should_autoactivate_ideas => new_activate_val}) 
                logger.info "just #{verb} auto_activate ideas for this question"
                render :json => {:message => "You've just #{verb.downcase} auto idea activation", :verb => verb}.to_json
              else
                render :json => {:message => "You've just #{verb.downcase} auto idea activation", :verb => verb}.to_json
              end
            }
        end
      end

  # GET /questions/new
  # GET /questions/new.xml
  def new
    @errors ||= []
    if signed_in?
      @registered = true
    end

    @question = Question.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @question }
    end
  end

  # GET /questions/1/edit
  def edit
    #@question = Question.find(params[:id])
  end
  
  def question_creation_validates?(question)
    # question.errors = []
    question.validate
    false unless question.errors.empty?
    #false
  end

  # POST /questions
  # POST /questions.xml
  def create
    #raise params[:question].inspect
    # 
    # @question = Question.new(params[:question].except('url').merge('visitor_identifier' => request.session_options[:id], 
    #                                                                 :ideas => params[:question]['question_ideas']))
    @question = Question.new(params[:question])
    #raise @question.inspect
    @question.validate_me
    unless @question.valid?
    	if signed_in?
      	   @registered = true
        end
      render :action => "new" and return
    end
    
    just_registered = true
    unless signed_in?
       logger.info "not signed in, getting ready to instantiate a new user from params in Questions#create"
      #try to register the user before adding the question
      @user = ::User.new(:email => params[:question]['email'], 
                         :password => params[:question]['password'], 
                         :password_confirmation => params[:question]['password'])
       unless @user.valid?
         flash[:registration_error] = "Sorry, we couldn't register you."
         #redirect_to 'questions/new' and return
         logger.info "Registration failed, here's the flash: #{flash.inspect}"
         render :action => "new" and return
       end
      if @user.save
        logger.info "just saved the user in Questions#create"
        sign_in @user
        just_registered = true
      else
        flash[:notice] = "Sorry, we couldn't register you."
        render :action => "new" and return
        #render :template => 'users/new' and return
      end
    end
    #at this point you have a current_user.  if you didn't, we would have redirected back with a validation error.
    
    @question_two = Question.new(params[:question].except('url').merge({'local_identifier' => current_user.id, 'visitor_identifier' => request.session_options[:id], :ideas => params[:question]['question_ideas']}))
    logger.info "question pre-save is #{@question.inspect}"
    respond_to do |format|
      retryable(:tries => 5) do
        if @question_two.save
          @question = @question_two
          earl = current_user.earls.create(:question_id => @question.id, :name => params[:question]['url'].strip)
          logger.info "Question was successfully created."
          session[:standard_flash] = "Congratulations. You are about to discover some great ideas.<br /> Send out your URL: #{@question.fq_earl} and watch what happens. <br /> You can further customize this site by following this link: <a href=\"#{@question.fq_earl}/admin\"> Manage this page </a>"
          ::ClearanceMailer.deliver_confirmation(current_user, @question.fq_earl) if just_registered
          format.html { redirect_to(@question.earl) }
          format.xml  { render :xml => @question, :status => :created, :location => @question }
        else
          logger.info "Question was not successfully created."
          format.html { render :action => "new" }
          format.xml  { render :xml => @question.errors, :status => :unprocessable_entity }
        end
      end
    end
  end

  # # PUT /questions/1
  # # PUT /questions/1.xml
  def update
     authenticate
     @meta = '<META NAME="ROBOTS" CONTENT="NOINDEX, NOFOLLOW">'
     @question = Question.find_by_name(params[:id])
     @earl = Earl.find params[:id]
     
     @partial_results_url = "#{@earl.name}/results"
     @choices = Choice.find(:all, :params => {:question_id => @question.id, :include_inactive => true})
     respond_to do |format|
        if @earl.update_attributes(params[:earl])

	    logger.info("Saving new information on earl")
	    flash[:notice] = 'Question settings saved successfully!'
	    logger.info("Saved new information on earl")
	    format.html {redirect_to:action => "admin"}
  	    # format.xml  { head :ok }
	else 
	    format.html { render :action => "admin"}
  	    #format.xml  { render :xml => @question.errors, :status => :unprocessable_entity }
        end
     end
  end
  def delete_logo
     authenticate
     @meta = '<META NAME="ROBOTS" CONTENT="NOINDEX, NOFOLLOW">'
     @question = Question.find_by_name(params[:id])
     @earl = Earl.find params[:id]
     
     @earl.logo = nil
     respond_to do |format|
        if @earl.save

	    logger.info("Deleting Logo from earl")
	    flash[:notice] = 'Question settings saved successfully!'
	    format.html {redirect_to:action => "admin"}
  	    # format.xml  { head :ok }
	else 
	    format.html { render :action => "admin"}
  	    #format.xml  { render :xml => @question.errors, :status => :unprocessable_entity }
        end

     end
  end



  # 
  # # DELETE /questions/1
  # # DELETE /questions/1.xml
  # def destroy
  #    @question = Question.find_by_name(params[:id])
  #   @question.destroy
  # 
  #   respond_to do |format|
  #     format.html { redirect_to(questions_url) }
  #     format.xml  { head :ok }
  #   end
  # end
end
