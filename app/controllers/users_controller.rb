class UsersController < ApplicationController
  before_action :set_user, except: %i[ index ]
  before_action :ensure_permission_to_change_user, only: %i[ update destroy ]

  def index
    @users = Current.account.users.active.alphabetically
  end

  def show
  end

  def edit
  end

  def update
    if @user.update(user_params)
      respond_to do |format|
        format.html { redirect_to @user }
        format.json { head :no_content }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.deactivate

    respond_to do |format|
      format.html { redirect_to users_path }
      format.json { head :no_content }
    end
  end

  private
    def set_user
      @user = Current.account.users.active.find(params[:id])
    end

    def ensure_permission_to_change_user
      head :forbidden unless Current.user.can_change?(@user)
    end

    def user_params
      params.expect(user: [ :name, :avatar ])
    end
end
