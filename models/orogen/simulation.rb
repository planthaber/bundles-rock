require 'models/blueprints/pose'

using_task_library 'simulation'

module Dev::Simulation
    module Mars
        device_type "Servo"
        device_type "Camera"
        device_type "DepthCamera"
        device_type "Actuator"
        device_type "Actuators"
        device_type "Joint"
        device_type "RangeFinder"
        device_type "IMU"
        device_type "Sonar"
    end
end

module Simulation
    DevMars = Dev::Simulation::Mars
    class SimulatedDevice < Syskit::Composition
        add Simulation::Mars, :as => "mars"
            
            def self.instanciate(*args)
                cmp_task = super
                cmp_task.task_child.should_configure_after cmp_task.mars_child.start_event
                cmp_task
            end
    end


    class Mars
        forward :physics_error => :failed

        def configure
            #orocos_task.enable_gui = true
            super
        end
    end
    
    class Actuators
        forward :lost_mars_connection => :failed 

        driver_for DevMars::Actuators, :as => "driver"
        class Cmp < SimulatedDevice
            add Simulation::Actuators, :as => "task"
            export task_child.command_port
            export task_child.status_port
            provides Base::ActuatorControlledSystemSrv, :as => 'actuator' 
        end
    end
    
    class MarsServo 
        forward :lost_mars_connection => :failed 
        driver_for DevMars::Servo, :as => "driver"
        class Cmp < SimulatedDevice
            add Simulation::MarsServo, :as => "task"
        end
    end
    
    class MarsIMU
        forward :lost_mars_connection => :failed 
        driver_for DevMars::IMU, :as => 'driver'
        provides Base::PoseSrv, :as  => "pose"

        class Cmp < SimulatedDevice
            add [DevMars::IMU,Base::OrientationSrv], :as => "task"
            export task_child.orientation_samples_port
            provides Base::PoseSrv, :as  => "pose"
        end
    end
    
    class Sonar
        forward :lost_mars_connection => :failed 
        driver_for DevMars::Sonar, :as => "driver"
    end
    
    class MarsCamera
        forward :lost_mars_connection => :failed 
        driver_for DevMars::Camera, :as => "driver"
        provides Base::ImageProviderSrv, :as => 'camera'

        class Cmp < SimulatedDevice
            add [DevMars::Camera,Base::ImageProviderSrv], :as => "task"
            export task_child.frame_port
            provides Base::ImageProviderSrv, :as => 'camera'
        end
    end
    
    class MarsActuator
        forward :lost_mars_connection => :failed 
        driver_for DevMars::Actuator, :as => "driver"
        
        dynamic_service  Base::ActuatorControlledSystemSrv, :as => 'dispatch' do
            component_model.argument "#{name}_mappings", :default => options[:mappings]
            provides  Base::ActuatorControlledSystemSrv, "status_out" => "status_#{name}", "command_in" => "cmd_#{name}"
        end
    
        class Cmp < SimulatedDevice
            argument :name

            add [DevMars::Actuator,Base::ActuatorControlledSystemSrv], :as => "task"
            export task_child.command_in_port
            export task_child.status_out_port
            provides Base::ActuatorControlledSystemSrv, :as => 'actuators'
        end
    
        def self.dispatch(name, mappings)
            model = self.specialize
            model.require_dynamic_service('dispatch', :as => name, :mappings => mappings)
            model
        end
    
        def configure
            each_data_service do |srv|
                if srv.fullfills?(Base::ActuatorControlledSystemSrv)
                    mappings = arguments["#{srv.name}_mappings"]
                    if !orocos_task.dispatch(srv.name, mappings)
                        puts "Could not dispatch the actuator set #{srv.name}"
                    end
                end
            end
            super
        end
    end

    def self.define_simulated_device(profile, name, model)
        device = profile.robot.device model, :as => name
        # The SimulatedDevice subclasses expect the MARS task,not the device
        # model. Resolve the task from the device definition by removing the
        # data service selection (#to_component_model)
        #
        # to_instance_requirements is there to convert the device object into
        # an InstanceRequirements object
        device = device.to_instance_requirements.to_component_model
        composition = composition_from_device(model)
        device = yield(device) if block_given?
        composition = composition.use('task' => device)
        profile.define name, composition
        model
    end

    def self.composition_from_device(device_model, options = nil)
        SimulatedDevice.each_submodel do |cmp_m|
            if cmp_m.task_child.fullfills?(device_model)
                return cmp_m
            end
        end
        raise ArgumentError, "no composition found to represent devices of type #{device_model} in MARS"
    end
end


class Syskit::Actions::Profile
    #
    # Instead of doing
    #   define 'dynamixel', Model
    #
    # Do
    #
    #   define_simulated_device 'dynamixel', Dev::Simulation::Sonar
    #
    def define_simulated_device(name, model, &block)
        Simulation.define_simulated_device(self, name, model, &block)
    end
end
