class CreateRecommendations < ActiveRecord::Migration[8.1]
  def change
    create_table :recommendations do |t|
      t.string :ticker
      t.string :action
      t.decimal :recommended_price
      t.decimal :current_price
      t.decimal :target_price
      t.decimal :stop_loss
      t.string :position_size
      t.string :time_horizon
      t.string :confidence
      t.string :video_title
      t.date :briefing_date
      t.text :notes

      t.timestamps
    end
  end
end
