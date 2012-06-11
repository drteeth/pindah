package <%= package %>

import android.support.v4.app.FragmentActivity

class INITIAL_ACTIVITY < FragmentActivity

  def onCreate(state)
    super state
    setContentView R.layout.main
  end

end
