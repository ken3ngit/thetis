#
#= DesktopController
#
#Original by::   Sysphonic
#Authors::   MORITA Shintaro
#Copyright:: Copyright (c) 2007-2011 MORITA Shintaro, Sysphonic. All rights reserved.
#License::   New BSD License (See LICENSE file)
#URL::   {http&#58;//sysphonic.com/}[http://sysphonic.com/]
#
#The Action-Controller about Desktop.
#
#== Note:
#
#* 
#
class DesktopController < ApplicationController
  protect_from_forgery :except => :drop_file
  layout 'base'

  include LoginChecker

  if $thetis_config[:menu]['req_login_desktop'] == '1'
    before_filter :check_login
  else
    before_filter :check_login, :only => [:post_label, :get_group_users]
  end
  before_filter :check_toy_owner, :only => [:drop_on_recyclebox, :on_toys_moved, :update_label]

  before_filter :only => [:configure, :update_config] do |controller|
    controller.check_auth(User::AUTH_DESKTOP)
  end


  #=== drop_file
  #
  #Drops a file on desktop.
  #
  def drop_file
    Log.add_info(request, '')   # Not to show passwords.

    if params[:file].nil? or params[:file].size <= 0
      render(:text => '')
      return
    end

    login_user = session[:login_user]

    if login_user.nil?
      login_user = User.authenticate(params[:user])

      if login_user.nil?
        render(:text => 'ERROR:' + t('msg.need_to_login'))
        return
      end
    end

    my_folder = login_user.get_my_folder
    if my_folder.nil?
      render(:text => 'ERROR:' + t('folder.cannot_find_my_folder'))
      return
    end

    original_filename = params[:file].original_filename
    title = ApplicationHelper.take_ncols(File.basename(original_filename, '.*'), 60, nil)

    item = Item.new_info(my_folder.id)
    item.title = title
    item.user_id = login_user.id
    item.save!

    params[:title] ||= title
    attachment = Attachment.create(params, item, 0)

    toy = Toy.new
    toy.user_id = login_user.id
    toy.xtype = Toy::XTYPE_ITEM
    toy.target_id = item.id
    toy.x, toy.y = DesktopHelper.find_empty_block login_user
    toy.save!

    render(:text => t('file.uploaded'))
  end

  #=== configure
  #
  #Shows form of configuration.
  #
  def configure
    Log.add_info(request, params.inspect)

    @yaml = ApplicationHelper.get_config_yaml
  end

  #=== update_config
  #
  #Updates configuration about desktop.
  #
  def update_config
    Log.add_info(request, params.inspect)

    @yaml = ApplicationHelper.get_config_yaml

    unless params[:desktop].nil? or params[:desktop].empty?
      @yaml[:desktop] = Hash.new if @yaml[:desktop].nil?

      params[:desktop].each do |key, val|
        @yaml[:desktop][key] = val
      end
      ApplicationHelper.save_config_yaml(@yaml)
    end

    flash[:notice] = t('msg.update_success')
    render(:partial => 'ajax_user_before_login', :layout => false)
  end

  #=== show
  #
  #Shows empty desktop.
  #
  def show
  end

  #=== open_desktop
  #
  #<Ajax>
  #Gets Toys (desktop items) for Login User.
  #
  def open_desktop
    Log.add_info(request, params.inspect)

    user = session[:login_user]

    is_config_desktop = false
    if user.nil?
      yaml = ApplicationHelper.get_config_yaml
      unless yaml[:desktop].nil?
        user_before_login = yaml[:desktop]['user_before_login']

        unless user_before_login.nil? or user_before_login.empty?
          begin
            user = User.find(user_before_login)
            is_config_desktop = true
          rescue StandardError => err
            Log.add_error(request, err)
          end
        end
      end
    end

    @toys = Toy.get_for_user(user)

    if is_config_desktop
      @toys.delete_if { |toy| 
              ret = false
              if toy.xtype == Toy::XTYPE_FOLDER
                begin
                  folder = Folder.find(toy.target_id)
                  ret = folder.my_folder?
                rescue
                end
              elsif toy.xtype == Toy::XTYPE_POSTLABEL
                ret = true
              end
              ret == true
            }
    end

    agent = request.env['HTTP_USER_AGENT']
    unless agent.nil?
      agent.scan(/\sMSIE\s?(\d+)[.](\d+)/){|m|
                  @ie_ver = m[0].to_i + (0.1 * m[1].to_i)
                }
    end

    render(:partial => 'ajax_get_desktop', :layout => false)
  end

  #=== get_news_tray
  #
  #<Ajax>
  #Gets Toys (desktop items) for Login User.
  #
  def get_news_tray
    Log.add_info(request, params.inspect)

    login_user = session[:login_user]

    @toys = []
    desktop_toys = Toy.get_for_user(login_user)

    deleted_ary = []

    # Item
    latests = Item.get_toys(login_user)
    deleted_ary = DesktopHelper.merge_toys desktop_toys, latests, deleted_ary
    @toys.concat(latests)

    # Comment
    latests = Comment.get_toys(login_user)
    deleted_ary = DesktopHelper.merge_toys desktop_toys, latests, deleted_ary
    @toys.concat(latests)

    # Workflow
    latests = Workflow.get_toys(login_user)
    deleted_ary = DesktopHelper.merge_toys desktop_toys, latests, deleted_ary
    @toys.concat(latests)

    # Schedule
    latests = Schedule.get_toys(login_user)
    deleted_ary = DesktopHelper.merge_toys desktop_toys, latests, deleted_ary
    @toys.concat(latests)

    deleted_ary.each do |toy|
      @toys.delete(toy)
    end

    ApplicationHelper.sort_updated_at(@toys)

    render(:partial => 'ajax_news_tray', :layout => false)
  end

  #=== drop_on_desktop
  #
  #<Ajax>
  #Receives dropped event on the desktop by Ajax.
  #
  def drop_on_desktop
    Log.add_info(request, params.inspect)

    login_user = session[:login_user]

    if login_user.nil?
      t = Time.now
      render(:text => (t.hour.to_s + t.min.to_s + t.sec.to_s))
      return
    end

    toy = Toy.new

    toy.user_id = login_user.id
    toy.x = params[:x].to_i
    toy.y = params[:y].to_i
    toy.xtype, toy.target_id = params[:id].split(':')
    toy.save!

    render(:text => toy.id.to_s)
  end

  #=== add_toy
  #
  #<Ajax>
  #Adds Toy on the desktop by Ajax.
  #
  def add_toy
    Log.add_info(request, params.inspect)

    login_user = session[:login_user]

    if login_user.nil?
      render(:text => '0')
      return
    end

    toy = Toy.new

    toy.user_id = login_user.id
    toy.xtype = params[:xtype]
    toy.target_id = params[:target_id].to_i
    toy.x, toy.y = DesktopHelper.find_empty_block(login_user)
    toy.save!

    render(:text => toy.id.to_s)
  end

  #=== drop_on_recyclebox
  #
  #<Ajax>
  #Receives dropped event on the recyclebox by Ajax.
  #
  def drop_on_recyclebox
    Log.add_info(request, params.inspect)

    login_user = session[:login_user]

    unless login_user.nil?
      Toy.destroy(params[:id])
    end

    render(:text => params[:id])
  end

  #=== on_toys_moved
  #
  #<Ajax>
  #Saves toys' new position by Ajax.
  #
  def on_toys_moved
    Log.add_info(request, params.inspect)

    login_user = session[:login_user]

    unless login_user.nil?
      begin
        toy = Toy.find(params[:id])
      rescue
      end

      unless toy.nil?
        toy.update_attributes({:x => params[:x], :y => params[:y]})
      end
    end

    render(:text => '')
  end

  #=== create_label
  #
  #<Ajax>
  #Creates a label as Toy instance.
  #
  def create_label
    Log.add_info(request, params.inspect)

    login_user = session[:login_user]

    if params[:thetisBoxEdit].empty?
      render(:partial => 'ajax_label', :layout => false)
      return
    end

    @toy = Toy.new

    @toy.xtype = Toy::XTYPE_LABEL
    @toy.message = params[:thetisBoxEdit]
    if login_user.nil?
      t = Time.now
      @toy.id = (t.hour.to_s + t.min.to_s + t.sec.to_s).to_i
      @toy.x, @toy.y = DesktopHelper.find_empty_block(login_user)
    else
      @toy.user_id = login_user.id
      @toy.x, @toy.y = DesktopHelper.find_empty_block(login_user)
      @toy.save!
    end

    render(:partial => 'ajax_label', :layout => false)
  end

  #=== update_label
  #
  #<Ajax>
  #Updates the label.
  #
  def update_label
    Log.add_info(request, params.inspect)

    login_user = session[:login_user]
    msg = params[:thetisBoxEdit]

    if params[:thetisBoxEdit].empty?
      render(:partial => 'ajax_label', :layout => false)
      return
    end

    if login_user.nil?
      @toy = Toy.new
      @toy.id = params[:id]
      @toy.xtype = Toy::XTYPE_LABEL
      @toy.x = params[:x]
      @toy.y = params[:y]
      @toy.message = msg
    else
      @toy = Toy.find(params[:id])
      @toy.update_attribute(:message, msg)
    end

    render(:partial => 'ajax_label', :layout => false)

  rescue StandardError => err
    Log.add_error(request, err)
 
    render(:partial => 'ajax_label', :layout => false)
  end

  #=== show_biorhythm
  #
  #Shows Biorhythm.
  #
  def show_biorhythm
    Log.add_info(request, params.inspect)
    render(:partial => 'biorhythm', :layout => false)
  end

  #=== post_label
  #
  #<Ajax>
  #Posts a label to specified users.
  #
  def post_label
    Log.add_info(request, params.inspect)

    login_user = session[:login_user]

    if params[:txaPostLabel].empty? or params[:post_to].empty?
      render(:text => '')
      return
    end

    params[:post_to].each do |user_id|
      user = User.find(user_id)
      toy = Toy.new

      toy.xtype = Toy::XTYPE_POSTLABEL
      toy.message = params[:txaPostLabel]
      toy.user_id = user.id
      toy.posted_by = login_user.id
      toy.x, toy.y = DesktopHelper.find_empty_block(user)
      toy.save!
    end

    flash[:notice] = t('msg.post_success')
    render(:partial => 'common/flash_notice', :layout => false)
  end

  #=== get_group_users
  #
  #<Ajax>
  #Gets Users in specified Group.
  #
  def get_group_users
    Log.add_info(request, params.inspect)

    @group_id = nil
    if !params[:thetisBoxSelKeeper].nil?
      @group_id = params[:thetisBoxSelKeeper].split(':').last
    elsif !params[:group_id].nil? and !params[:group_id].empty?
      @group_id = params[:group_id]
    end

    @users = Group.get_users(@group_id)

    render(:partial => 'ajax_select_users', :layout => false)
  end

 private
  #=== check_toy_owner
  #
  #Filter method to check if current User is owner of the specified Toy.
  #
  def check_toy_owner
    return if params[:id].nil? or params[:id].empty? or session[:login_user].nil?

    begin
      owner_id = Toy.find(params[:id]).user_id
    rescue
      owner_id = -1
    end
    login_user = session[:login_user]
    if !login_user.admin?(User::AUTH_DESKTOP) and owner_id != login_user.id
      Log.add_check(request, '[check_toy_owner]'+request.to_s)

      flash[:notice] = t('msg.need_to_be_owner')
      redirect_to(:controller => 'desktop', :action => 'show')
    end
  end
end