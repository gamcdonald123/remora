class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.string :docker_id, null: false
      t.string :container_name
      t.string :kind, null: false
      t.integer :exit_code
      t.datetime :occurred_at, null: false, precision: 6

      t.index [ :docker_id, :occurred_at ]
      t.index :occurred_at
    end
  end
end
