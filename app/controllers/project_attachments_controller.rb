class ProjectAttachmentsController < ApplicationController
  helper SearchHelper
  before_action :find_optional_project
  before_action :filter
  menu_item :all_files

  @@module_names_to_container_types = { :issue_tracking => 'issues', :news => 'news', :documents => 'documents', :wiki => 'wiki_pages', :files => 'projects', :boards => 'messages' }

  def index
    params[:project_id].present? ? get_attachment_from_project(params[:project_id]) : get_all_attachments
    @limit = per_page_option
    @attachments_count = @all_attachments.size
    @attachments_pages = Paginator.new @attachments_count, @limit, params[:page]
    @offset = @attachments_pages.offset

    @attachments = if @all_attachments.is_a? Array
                     @all_attachments[@offset..(@offset + @limit - 1)]
                   else
                     @all_attachments.offset(@offset).limit(@limit)
                   end
  end
  private

  def filter
    @question = params[:q] || ""
    @question.strip!
    @all_words = params[:all_words] ? params[:all_words].present? : true
    @titles_only = params[:titles_only] ? params[:titles_only].present? : false

    # extract tokens from the question
    # eg. hello "bye bye" => ["hello", "bye bye"]
    @tokens = @question.scan(%r{((\s|^)"[\s\w]+"(\s|$)|\S+)}).collect {|m| m.first.gsub(%r{(^\s*"\s*|\s*"\s*$)}, '')}
    # tokens must be at least 2 characters long
    @tokens = @tokens.uniq.select {|w| w.length > 1 }
    # no more than 5 tokens to search for
    @tokens.slice! 5..-1 if @tokens.size > 5
  end


  def get_attachment_from_project(project_id)
    begin
      @project = Project.find(project_id)
      # find enabled project modules
      @enabled_module_names = @project.enabled_modules.map(&:name)
      # find available container types
      @container_types = @@module_names_to_container_types.select { |k, _| @enabled_module_names.include?(k.to_s) }.map { |k, v| v } << 'versions'
      # user select container types from available
      @scope = @container_types.select {|t| params[t]}
      @scope = @container_types if @scope.empty?
      @all_attachments = Attachment.search_attachments_for_projects [@project.id],
                                                                    @tokens,
                                                                    :scope => @scope,
                                                                    :all_words => @all_words,
                                                                    :titles_only => @titles_only
      # use only select (not select!) to have a compatibility with ruby 1.8.7
      unless User.current.admin?
        @all_attachments = @all_attachments.select {|a| a.visible? }
      end
      @all_attachments.sort! {|a1, a2| a2.created_on <=> a1.created_on }
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end

  def get_all_attachments
    @projects ||= Project.visible.
        includes(:enabled_modules).
        references(:enabled_modules)
    # group projects by enabled modules
    container_types_to_projects = Hash.new { |h, k| h[k] = [] }
    @projects.each do |project|
      enabled_module_names = project.enabled_modules.map(&:name)
      container_types = @@module_names_to_container_types.select { |k, _| enabled_module_names.include?(k.to_s) }.map { |k, v| v } << 'versions'
      container_types_to_projects[container_types] << project.id
    end
    @container_types = @@module_names_to_container_types.map { |k, v| v } << 'versions'
    # user select container types from available
    @scope = @container_types.select {|t| params[t]}
    @scope = @container_types if @scope.empty?
    @all_attachments = []
    # search attachments into
    # cond = Attachment.selection
    cond = " "
    container_types_to_projects.each do |scope, projects|
      # user select container types from available
      scope = scope.select { |t| @scope.include? t }

      scope_cond = Attachment.search_attachments_for_projects_bis(projects,
                                                                  @tokens,
                                                                  :scope => scope,
                                                                  :all_words => @all_words,
                                                                  :titles_only => @titles_only)
      unless scope_cond.empty?
        cond << scope_cond
        cond << ' OR '
      end
    end
    cond << '(1 = 2) '

    @all_attachments= Attachment.where( cond).selection.order_by_created_on
    # use only select (not select!) to have a compatibility with ruby 1.8.7
    unless User.current.admin?
      @all_attachments = @all_attachments.select {|a| a.visible? }
    end
  end
end
