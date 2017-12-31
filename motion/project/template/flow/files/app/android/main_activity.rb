class MainActivity < Android::Support::V7::App::AppCompatActivity
  def onCreate(savedInstanceState)
    Store.context = self
    super
  end
end
